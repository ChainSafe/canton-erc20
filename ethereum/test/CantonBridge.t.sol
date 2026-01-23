// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {CantonBridge} from "../contracts/core/CantonBridge.sol";
import {ICantonBridge} from "../contracts/interfaces/ICantonBridge.sol";
import {MockERC20, MockUSDC, MockPROMPT} from "../contracts/mocks/MockERC20.sol";

/**
 * @title CantonBridgeTest
 * @notice Unit tests for CantonBridge contract
 */
contract CantonBridgeTest is Test {
    CantonBridge public bridge;
    MockUSDC public usdc;
    MockPROMPT public prompt;

    address public admin = makeAddr("admin");
    address public relayer = makeAddr("relayer");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    // Canton fingerprints (32 bytes)
    bytes32 public constant FINGERPRINT_1 = bytes32(uint256(0x1220abcdef1234567890abcdef1234567890abcdef1234567890abcdef123456));
    bytes32 public constant FINGERPRINT_2 = bytes32(uint256(0x1220fedcba0987654321fedcba0987654321fedcba0987654321fedcba098765));

    // Canton token IDs
    bytes32 public constant USDC_CANTON_ID = keccak256("canton:usdc");
    bytes32 public constant PROMPT_CANTON_ID = keccak256("canton:prompt");

    uint256 public constant INITIAL_BALANCE = 1_000_000e6; // 1M USDC

    function setUp() public {
        vm.startPrank(admin);

        // Deploy contracts
        bridge = new CantonBridge(admin);
        usdc = new MockUSDC();
        prompt = new MockPROMPT();

        // Setup roles
        bridge.grantRole(bridge.RELAYER_ROLE(), relayer);

        // Register tokens
        bridge.registerToken(address(usdc), USDC_CANTON_ID);
        bridge.registerToken(address(prompt), PROMPT_CANTON_ID);

        vm.stopPrank();

        // Mint tokens to users
        usdc.mint(user1, INITIAL_BALANCE);
        usdc.mint(user2, INITIAL_BALANCE);
        prompt.mint(user1, 1000e18);
    }

    // =========================================================================
    // DEPOSIT TESTS
    // =========================================================================

    function test_depositToCanton_success() public {
        uint256 amount = 1000e6;

        vm.startPrank(user1);
        usdc.approve(address(bridge), amount);

        vm.expectEmit(true, true, true, true);
        emit ICantonBridge.DepositToCanton(address(usdc), user1, amount, FINGERPRINT_1, 1);

        uint256 nonce = bridge.depositToCanton(address(usdc), amount, FINGERPRINT_1);
        vm.stopPrank();

        assertEq(nonce, 1, "Nonce should be 1");
        assertEq(bridge.getLockedBalance(address(usdc)), amount, "Locked balance should match");
        assertEq(usdc.balanceOf(address(bridge)), amount, "Bridge should hold tokens");
        assertEq(usdc.balanceOf(user1), INITIAL_BALANCE - amount, "User balance should decrease");
    }

    function test_depositToCanton_multipleDeposits() public {
        uint256 amount = 100e6;

        vm.startPrank(user1);
        usdc.approve(address(bridge), amount * 3);

        uint256 nonce1 = bridge.depositToCanton(address(usdc), amount, FINGERPRINT_1);
        uint256 nonce2 = bridge.depositToCanton(address(usdc), amount, FINGERPRINT_1);
        uint256 nonce3 = bridge.depositToCanton(address(usdc), amount, FINGERPRINT_2);
        vm.stopPrank();

        assertEq(nonce1, 1, "First nonce should be 1");
        assertEq(nonce2, 2, "Second nonce should be 2");
        assertEq(nonce3, 3, "Third nonce should be 3");
        assertEq(bridge.getLockedBalance(address(usdc)), amount * 3, "Locked balance should accumulate");
    }

    function test_depositToCanton_revert_tokenNotRegistered() public {
        MockERC20 unregistered = new MockERC20("Unregistered", "UNR", 18);
        unregistered.mint(user1, 1000e18);

        vm.startPrank(user1);
        unregistered.approve(address(bridge), 100e18);

        vm.expectRevert(abi.encodeWithSelector(ICantonBridge.TokenNotRegistered.selector, address(unregistered)));
        bridge.depositToCanton(address(unregistered), 100e18, FINGERPRINT_1);
        vm.stopPrank();
    }

    function test_depositToCanton_revert_zeroAmount() public {
        vm.startPrank(user1);
        usdc.approve(address(bridge), 1000e6);

        vm.expectRevert(ICantonBridge.InvalidAmount.selector);
        bridge.depositToCanton(address(usdc), 0, FINGERPRINT_1);
        vm.stopPrank();
    }

    function test_depositToCanton_revert_invalidFingerprint() public {
        vm.startPrank(user1);
        usdc.approve(address(bridge), 1000e6);

        vm.expectRevert(abi.encodeWithSelector(ICantonBridge.InvalidFingerprint.selector, bytes32(0)));
        bridge.depositToCanton(address(usdc), 1000e6, bytes32(0));
        vm.stopPrank();
    }

    function test_depositToCanton_revert_whenPaused() public {
        vm.prank(admin);
        bridge.pause();

        vm.startPrank(user1);
        usdc.approve(address(bridge), 1000e6);

        vm.expectRevert();
        bridge.depositToCanton(address(usdc), 1000e6, FINGERPRINT_1);
        vm.stopPrank();
    }

    // =========================================================================
    // WITHDRAWAL TESTS
    // =========================================================================

    function test_withdrawFromCanton_success() public {
        // Setup relayer with proper key
        uint256 relayerKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        address relayerAddr = vm.addr(relayerKey);
        vm.startPrank(admin);
        bridge.grantRole(bridge.RELAYER_ROLE(), relayerAddr);
        vm.stopPrank();

        // First deposit
        uint256 depositAmount = 1000e6;
        vm.startPrank(user1);
        usdc.approve(address(bridge), depositAmount);
        bridge.depositToCanton(address(usdc), depositAmount, FINGERPRINT_1);
        vm.stopPrank();

        // Prepare withdrawal
        uint256 withdrawAmount = 500e6;
        bytes32 withdrawalId = keccak256("withdrawal-1");

        // Create proof (signed by relayer)
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                address(usdc),
                withdrawAmount,
                user2,
                withdrawalId,
                block.chainid,
                address(bridge)
            )
        );
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(relayerKey, ethSignedHash);
        bytes memory proof = abi.encodePacked(r, s, v);

        // Execute withdrawal
        vm.prank(relayerAddr);
        bridge.withdrawFromCanton(address(usdc), withdrawAmount, user2, withdrawalId, proof);

        assertEq(usdc.balanceOf(user2), INITIAL_BALANCE + withdrawAmount, "User should receive tokens");
        assertEq(bridge.getLockedBalance(address(usdc)), depositAmount - withdrawAmount, "Locked balance should decrease");
        assertTrue(bridge.isWithdrawalProcessed(withdrawalId), "Withdrawal should be marked processed");
    }

    function test_withdrawFromCanton_revert_notRelayer() public {
        bytes32 withdrawalId = keccak256("withdrawal-1");
        bytes memory dummyProof = new bytes(65);

        vm.expectRevert();
        vm.prank(user1);
        bridge.withdrawFromCanton(address(usdc), 100e6, user1, withdrawalId, dummyProof);
    }

    function test_withdrawFromCanton_revert_alreadyProcessed() public {
        // Setup relayer with proper key
        uint256 relayerKey = 0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890;
        address relayerAddr = vm.addr(relayerKey);
        vm.startPrank(admin);
        bridge.grantRole(bridge.RELAYER_ROLE(), relayerAddr);
        vm.stopPrank();

        // First deposit
        uint256 depositAmount = 1000e6;
        vm.startPrank(user1);
        usdc.approve(address(bridge), depositAmount);
        bridge.depositToCanton(address(usdc), depositAmount, FINGERPRINT_1);
        vm.stopPrank();

        bytes32 withdrawalId = keccak256("withdrawal-1");
        uint256 withdrawAmount = 100e6;

        // Create valid proof
        bytes32 messageHash = keccak256(
            abi.encodePacked(address(usdc), withdrawAmount, user2, withdrawalId, block.chainid, address(bridge))
        );
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(relayerKey, ethSignedHash);
        bytes memory proof = abi.encodePacked(r, s, v);

        // First withdrawal succeeds
        vm.prank(relayerAddr);
        bridge.withdrawFromCanton(address(usdc), withdrawAmount, user2, withdrawalId, proof);

        // Second withdrawal with same ID should fail
        vm.expectRevert(abi.encodeWithSelector(ICantonBridge.WithdrawalAlreadyProcessed.selector, withdrawalId));
        vm.prank(relayerAddr);
        bridge.withdrawFromCanton(address(usdc), withdrawAmount, user2, withdrawalId, proof);
    }

    // =========================================================================
    // RATE LIMIT TESTS
    // =========================================================================

    function test_rateLimit_enforced() public {
        // Set rate limit: 500 USDC per hour
        vm.prank(admin);
        bridge.setTokenRateLimit(address(usdc), 500e6, 1 hours);

        vm.startPrank(user1);
        usdc.approve(address(bridge), 1000e6);

        // First deposit within limit should succeed
        bridge.depositToCanton(address(usdc), 300e6, FINGERPRINT_1);

        // Second deposit within limit should succeed
        bridge.depositToCanton(address(usdc), 200e6, FINGERPRINT_1);

        // Third deposit should fail (exceeds limit)
        vm.expectRevert();
        bridge.depositToCanton(address(usdc), 100e6, FINGERPRINT_1);
        vm.stopPrank();
    }

    function test_rateLimit_resetsAfterPeriod() public {
        // Set rate limit: 500 USDC per hour
        vm.prank(admin);
        bridge.setTokenRateLimit(address(usdc), 500e6, 1 hours);

        vm.startPrank(user1);
        usdc.approve(address(bridge), 1000e6);

        // Use full limit
        bridge.depositToCanton(address(usdc), 500e6, FINGERPRINT_1);

        // Should fail now
        vm.expectRevert();
        bridge.depositToCanton(address(usdc), 100e6, FINGERPRINT_1);

        // Advance time past reset
        vm.warp(block.timestamp + 1 hours + 1);

        // Should succeed now
        bridge.depositToCanton(address(usdc), 400e6, FINGERPRINT_1);
        vm.stopPrank();
    }

    // =========================================================================
    // ADMIN TESTS
    // =========================================================================

    function test_pause_unpause() public {
        vm.prank(admin);
        bridge.pause();
        assertTrue(bridge.paused(), "Bridge should be paused");

        vm.prank(admin);
        bridge.unpause();
        assertFalse(bridge.paused(), "Bridge should be unpaused");
    }

    function test_registerToken() public {
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);
        bytes32 cantonId = keccak256("canton:new");

        vm.prank(admin);
        bridge.registerToken(address(newToken), cantonId);

        assertTrue(bridge.isTokenRegistered(address(newToken)), "Token should be registered");
    }

    function test_deregisterToken() public {
        vm.prank(admin);
        bridge.deregisterToken(address(usdc));

        assertFalse(bridge.isTokenRegistered(address(usdc)), "Token should be deregistered");
    }

    function test_emergencyWithdraw() public {
        // First deposit
        uint256 depositAmount = 1000e6;
        vm.startPrank(user1);
        usdc.approve(address(bridge), depositAmount);
        bridge.depositToCanton(address(usdc), depositAmount, FINGERPRINT_1);
        vm.stopPrank();

        // Emergency withdrawal
        address emergencyRecipient = makeAddr("emergency");
        vm.prank(admin);
        bridge.emergencyWithdraw(address(usdc), depositAmount, emergencyRecipient);

        assertEq(usdc.balanceOf(emergencyRecipient), depositAmount, "Emergency recipient should receive tokens");
        assertEq(bridge.getLockedBalance(address(usdc)), 0, "Locked balance should be zero");
    }

    // =========================================================================
    // VIEW FUNCTION TESTS
    // =========================================================================

    function test_getDepositNonce() public {
        vm.startPrank(user1);
        usdc.approve(address(bridge), 300e6);

        assertEq(bridge.getDepositNonce(user1), 0, "Initial nonce should be 0");

        bridge.depositToCanton(address(usdc), 100e6, FINGERPRINT_1);
        assertEq(bridge.getDepositNonce(user1), 1, "Nonce should be 1 after first deposit");

        bridge.depositToCanton(address(usdc), 100e6, FINGERPRINT_1);
        assertEq(bridge.getDepositNonce(user1), 2, "Nonce should be 2 after second deposit");
        vm.stopPrank();
    }

    function test_getCantonTokenId() public view {
        assertEq(bridge.getCantonTokenId(address(usdc)), USDC_CANTON_ID, "Canton ID should match");
        assertEq(bridge.getCantonTokenId(address(prompt)), PROMPT_CANTON_ID, "Canton ID should match");
    }

    // =========================================================================
    // LARGE WITHDRAWAL SECURITY TESTS
    // =========================================================================

    function test_largeWithdrawal_storesAllParameters() public {
        // Setup relayer with proper key
        uint256 relayerKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        address relayerAddr = vm.addr(relayerKey);
        vm.startPrank(admin);
        bridge.grantRole(bridge.RELAYER_ROLE(), relayerAddr);
        // Set large withdrawal threshold
        bridge.setLargeWithdrawalThreshold(address(usdc), 100e6);
        vm.stopPrank();

        // First deposit
        uint256 depositAmount = 1000e6;
        vm.startPrank(user1);
        usdc.approve(address(bridge), depositAmount);
        bridge.depositToCanton(address(usdc), depositAmount, FINGERPRINT_1);
        vm.stopPrank();

        // Prepare large withdrawal (above threshold)
        uint256 withdrawAmount = 500e6;
        bytes32 withdrawalId = keccak256("large-withdrawal-1");

        // Create proof (signed by relayer)
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                address(usdc),
                withdrawAmount,
                user2,
                withdrawalId,
                block.chainid,
                address(bridge)
            )
        );
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(relayerKey, ethSignedHash);
        bytes memory proof = abi.encodePacked(r, s, v);

        // Queue the large withdrawal
        vm.prank(relayerAddr);
        bridge.withdrawFromCanton(address(usdc), withdrawAmount, user2, withdrawalId, proof);

        // Verify all parameters are stored in the queued withdrawal
        (address storedToken, uint256 storedAmount, address storedRecipient, uint256 executeAfter) = bridge.queuedWithdrawals(withdrawalId);
        assertEq(storedToken, address(usdc), "Stored token should match");
        assertEq(storedAmount, withdrawAmount, "Stored amount should match");
        assertEq(storedRecipient, user2, "Stored recipient should match");
        assertGt(executeAfter, block.timestamp, "Execute after should be in future");
    }

    function test_largeWithdrawal_executesWithStoredParams() public {
        // Setup relayer with proper key
        uint256 relayerKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        address relayerAddr = vm.addr(relayerKey);
        vm.startPrank(admin);
        bridge.grantRole(bridge.RELAYER_ROLE(), relayerAddr);
        bridge.setLargeWithdrawalThreshold(address(usdc), 100e6);
        vm.stopPrank();

        // First deposit
        uint256 depositAmount = 1000e6;
        vm.startPrank(user1);
        usdc.approve(address(bridge), depositAmount);
        bridge.depositToCanton(address(usdc), depositAmount, FINGERPRINT_1);
        vm.stopPrank();

        // Queue large withdrawal
        uint256 withdrawAmount = 500e6;
        bytes32 withdrawalId = keccak256("large-withdrawal-2");

        bytes32 messageHash = keccak256(
            abi.encodePacked(address(usdc), withdrawAmount, user2, withdrawalId, block.chainid, address(bridge))
        );
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(relayerKey, ethSignedHash);
        bytes memory proof = abi.encodePacked(r, s, v);

        vm.prank(relayerAddr);
        bridge.withdrawFromCanton(address(usdc), withdrawAmount, user2, withdrawalId, proof);

        // Get stored executeAfter time
        (,,, uint256 executeAfter) = bridge.queuedWithdrawals(withdrawalId);

        // Warp past time lock
        vm.warp(executeAfter + 1);

        // Execute uses stored parameters (no params needed except withdrawalId)
        uint256 user2BalanceBefore = usdc.balanceOf(user2);
        vm.prank(relayerAddr);
        bridge.executeLargeWithdrawal(withdrawalId);

        // Verify tokens transferred using stored params
        assertEq(usdc.balanceOf(user2), user2BalanceBefore + withdrawAmount, "User2 should receive stored amount");
        assertTrue(bridge.isWithdrawalProcessed(withdrawalId), "Withdrawal should be processed");
    }

    function test_largeWithdrawal_cannotExecuteBeforeTimelock() public {
        // Setup relayer with proper key
        uint256 relayerKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        address relayerAddr = vm.addr(relayerKey);
        vm.startPrank(admin);
        bridge.grantRole(bridge.RELAYER_ROLE(), relayerAddr);
        bridge.setLargeWithdrawalThreshold(address(usdc), 100e6);
        vm.stopPrank();

        // Deposit
        uint256 depositAmount = 1000e6;
        vm.startPrank(user1);
        usdc.approve(address(bridge), depositAmount);
        bridge.depositToCanton(address(usdc), depositAmount, FINGERPRINT_1);
        vm.stopPrank();

        // Queue large withdrawal
        bytes32 withdrawalId = keccak256("large-withdrawal-3");
        bytes32 messageHash = keccak256(
            abi.encodePacked(address(usdc), uint256(500e6), user2, withdrawalId, block.chainid, address(bridge))
        );
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(relayerKey, ethSignedHash);
        bytes memory proof = abi.encodePacked(r, s, v);

        vm.prank(relayerAddr);
        bridge.withdrawFromCanton(address(usdc), 500e6, user2, withdrawalId, proof);

        // Try to execute immediately (should fail)
        vm.expectRevert("Withdrawal still time-locked");
        vm.prank(relayerAddr);
        bridge.executeLargeWithdrawal(withdrawalId);
    }

    function test_largeWithdrawal_cancelEmitsEvent() public {
        // Setup relayer with proper key
        uint256 relayerKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        address relayerAddr = vm.addr(relayerKey);
        vm.startPrank(admin);
        bridge.grantRole(bridge.RELAYER_ROLE(), relayerAddr);
        bridge.setLargeWithdrawalThreshold(address(usdc), 100e6);
        vm.stopPrank();

        // Deposit
        uint256 depositAmount = 1000e6;
        vm.startPrank(user1);
        usdc.approve(address(bridge), depositAmount);
        bridge.depositToCanton(address(usdc), depositAmount, FINGERPRINT_1);
        vm.stopPrank();

        // Queue large withdrawal
        bytes32 withdrawalId = keccak256("large-withdrawal-4");
        bytes32 messageHash = keccak256(
            abi.encodePacked(address(usdc), uint256(500e6), user2, withdrawalId, block.chainid, address(bridge))
        );
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(relayerKey, ethSignedHash);
        bytes memory proof = abi.encodePacked(r, s, v);

        vm.prank(relayerAddr);
        bridge.withdrawFromCanton(address(usdc), 500e6, user2, withdrawalId, proof);

        // Cancel should emit event
        vm.prank(admin);
        bridge.cancelLargeWithdrawal(withdrawalId);

        // Verify queued withdrawal is cleared
        (address storedToken,,, uint256 executeAfter) = bridge.queuedWithdrawals(withdrawalId);
        assertEq(storedToken, address(0), "Token should be cleared");
        assertEq(executeAfter, 0, "ExecuteAfter should be cleared");
    }
}
