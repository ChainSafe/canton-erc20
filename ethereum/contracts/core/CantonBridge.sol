// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {ICantonBridge} from "../interfaces/ICantonBridge.sol";
import {IBridgeEvents} from "../interfaces/IBridgeEvents.sol";
import {RateLimiter} from "../security/RateLimiter.sol";

/**
 * @title CantonBridge
 * @notice ERC-20 bridge contract for Canton Network
 * @dev Enables bidirectional token transfers between EVM chains and Canton Network
 *
 * ## Architecture
 * - Deposits: Users lock ERC-20 tokens, middleware mints CIP-56 tokens on Canton
 * - Withdrawals: Canton burns CIP-56 tokens, relayer releases ERC-20 tokens here
 *
 * ## Security
 * - Role-based access control (ADMIN, RELAYER, PAUSER)
 * - Reentrancy protection on all state-changing functions
 * - Rate limiting per token
 * - Pausable for emergency stops
 * - Signature verification for withdrawals
 */
contract CantonBridge is ICantonBridge, IBridgeEvents, ReentrancyGuard, Pausable, AccessControl, RateLimiter {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    /// @notice Role for relayer operations (withdrawals)
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    /// @notice Role for pausing/unpausing the bridge
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role for administrative operations
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Minimum fingerprint length (Canton uses 32-byte fingerprints)
    uint256 private constant MIN_FINGERPRINT_LENGTH = 32;

    // =========================================================================
    // STATE VARIABLES
    // =========================================================================

    /// @notice Registered tokens that can be bridged
    mapping(address => bool) public registeredTokens;

    /// @notice Deposit nonces per user (for tracking/deduplication)
    mapping(address => uint256) public depositNonces;

    /// @notice Processed withdrawal IDs (replay protection)
    mapping(bytes32 => bool) public processedWithdrawals;

    /// @notice Locked balances per token
    mapping(address => uint256) public lockedBalances;

    /// @notice Canton token ID mapping (EVM address => Canton CIP-56 ID)
    mapping(address => bytes32) public cantonTokenIds;

    /// @notice Time lock delay for large withdrawals (in seconds)
    uint256 public timeLockDelay;

    /// @notice Threshold for large withdrawals (per token)
    mapping(address => uint256) public largeWithdrawalThresholds;

    /// @notice Queued withdrawal data for time-locked withdrawals
    struct QueuedWithdrawal {
        address token;
        uint256 amount;
        address recipient;
        uint256 executeAfter;
    }

    /// @notice Queued large withdrawals with full parameters
    mapping(bytes32 => QueuedWithdrawal) public queuedWithdrawals;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    /**
     * @notice Initialize the Canton Bridge
     * @param admin The initial admin address
     */
    constructor(address admin) {
        if (admin == address(0)) revert InvalidRecipient(admin);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        timeLockDelay = 1 hours;
    }

    // =========================================================================
    // DEPOSIT (EVM -> Canton)
    // =========================================================================

    /**
     * @inheritdoc ICantonBridge
     */
    function depositToCanton(
        address token,
        uint256 amount,
        bytes32 cantonRecipient
    ) external nonReentrant whenNotPaused returns (uint256 nonce) {
        // Validate inputs
        if (!registeredTokens[token]) {
            revert TokenNotRegistered(token);
        }
        if (amount == 0) {
            revert InvalidAmount();
        }
        if (!_isValidFingerprint(cantonRecipient)) {
            revert InvalidFingerprint(cantonRecipient);
        }

        // Check rate limit
        _checkAndUpdateRateLimit(token, amount);

        // Transfer tokens to bridge (escrow)
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        lockedBalances[token] += amount;

        // Increment and return nonce
        nonce = ++depositNonces[msg.sender];

        emit DepositToCanton(token, msg.sender, amount, cantonRecipient, nonce);
    }

    // =========================================================================
    // WITHDRAWAL (Canton -> EVM)
    // =========================================================================

    /**
     * @inheritdoc ICantonBridge
     */
    function withdrawFromCanton(
        address token,
        uint256 amount,
        address recipient,
        bytes32 withdrawalId,
        bytes calldata proof
    ) external nonReentrant whenNotPaused onlyRole(RELAYER_ROLE) {
        // Validate inputs
        if (processedWithdrawals[withdrawalId]) {
            revert WithdrawalAlreadyProcessed(withdrawalId);
        }
        if (!registeredTokens[token]) {
            revert TokenNotRegistered(token);
        }
        if (amount == 0) {
            revert InvalidAmount();
        }
        if (recipient == address(0)) {
            revert InvalidRecipient(recipient);
        }

        // Verify withdrawal proof (signature from Canton middleware)
        if (!_verifyWithdrawalProof(token, amount, recipient, withdrawalId, proof)) {
            revert InvalidWithdrawalProof();
        }

        // Check for large withdrawal time lock
        uint256 threshold = largeWithdrawalThresholds[token];
        if (threshold > 0 && amount >= threshold) {
            _handleLargeWithdrawal(withdrawalId, token, amount, recipient);
            return;
        }

        // Execute withdrawal
        _executeWithdrawal(token, amount, recipient, withdrawalId);
    }

    /**
     * @notice Execute a queued large withdrawal after time lock
     * @param withdrawalId The withdrawal identifier
     * @dev Uses stored parameters to prevent parameter manipulation attacks
     */
    function executeLargeWithdrawal(
        bytes32 withdrawalId
    ) external nonReentrant whenNotPaused onlyRole(RELAYER_ROLE) {
        QueuedWithdrawal storage queued = queuedWithdrawals[withdrawalId];

        // Check withdrawal exists
        if (queued.executeAfter == 0) {
            revert WithdrawalAlreadyProcessed(withdrawalId);
        }

        // Check time-lock expired
        if (block.timestamp < queued.executeAfter) {
            revert("Withdrawal still time-locked");
        }

        // Extract stored parameters (CEI pattern - read before delete)
        address token = queued.token;
        uint256 amount = queued.amount;
        address recipient = queued.recipient;

        // Clear queued withdrawal BEFORE execution (prevents reentrancy)
        delete queuedWithdrawals[withdrawalId];

        // Execute with stored parameters
        _executeWithdrawal(token, amount, recipient, withdrawalId);
    }

    /**
     * @notice Cancel a queued large withdrawal
     * @param withdrawalId The withdrawal identifier
     */
    function cancelLargeWithdrawal(bytes32 withdrawalId) external onlyRole(ADMIN_ROLE) {
        if (queuedWithdrawals[withdrawalId].executeAfter == 0) {
            revert WithdrawalAlreadyProcessed(withdrawalId);
        }
        delete queuedWithdrawals[withdrawalId];
        emit LargeWithdrawalCancelled(withdrawalId);
    }

    // =========================================================================
    // INTERNAL FUNCTIONS
    // =========================================================================

    /**
     * @notice Validate Canton fingerprint format
     * @dev Canton fingerprints are 32-byte multihash values
     * @param fingerprint The fingerprint to validate
     * @return True if valid
     */
    function _isValidFingerprint(bytes32 fingerprint) internal pure returns (bool) {
        // Canton fingerprints should not be zero
        return fingerprint != bytes32(0);
    }

    /**
     * @notice Verify withdrawal proof signature
     * @param token The token address
     * @param amount The withdrawal amount
     * @param recipient The recipient address
     * @param withdrawalId The withdrawal identifier
     * @param proof The signature proof
     * @return True if proof is valid
     */
    function _verifyWithdrawalProof(
        address token,
        uint256 amount,
        address recipient,
        bytes32 withdrawalId,
        bytes calldata proof
    ) internal view returns (bool) {
        // Reconstruct message hash
        bytes32 messageHash = keccak256(
            abi.encodePacked(token, amount, recipient, withdrawalId, block.chainid, address(this))
        );

        // Convert to Ethereum signed message hash
        bytes32 ethSignedHash = messageHash.toEthSignedMessageHash();

        // Recover signer from signature
        address signer = ethSignedHash.recover(proof);

        // Verify signer has RELAYER_ROLE
        return hasRole(RELAYER_ROLE, signer);
    }

    /**
     * @notice Handle large withdrawal with time lock
     * @param withdrawalId The withdrawal identifier
     * @param token The token address
     * @param amount The withdrawal amount
     * @param recipient The recipient address
     * @dev Stores ALL parameters to prevent manipulation during time lock period
     */
    function _handleLargeWithdrawal(
        bytes32 withdrawalId,
        address token,
        uint256 amount,
        address recipient
    ) internal {
        uint256 executeAfter = block.timestamp + timeLockDelay;

        // Store ALL parameters, not just timestamp (security fix)
        queuedWithdrawals[withdrawalId] = QueuedWithdrawal({
            token: token,
            amount: amount,
            recipient: recipient,
            executeAfter: executeAfter
        });

        emit LargeWithdrawalQueued(withdrawalId, token, amount, executeAfter);
    }

    /**
     * @notice Execute a withdrawal
     * @param token The token address
     * @param amount The withdrawal amount
     * @param recipient The recipient address
     * @param withdrawalId The withdrawal identifier
     */
    function _executeWithdrawal(
        address token,
        uint256 amount,
        address recipient,
        bytes32 withdrawalId
    ) internal {
        // Check locked balance
        if (lockedBalances[token] < amount) {
            revert InsufficientLockedBalance(token, amount, lockedBalances[token]);
        }

        // Mark as processed
        processedWithdrawals[withdrawalId] = true;

        // Update balance and transfer
        lockedBalances[token] -= amount;
        IERC20(token).safeTransfer(recipient, amount);

        emit WithdrawalFromCanton(token, recipient, amount, bytes32(0), withdrawalId);
        emit WithdrawalProcessed(withdrawalId, true);
    }

    // =========================================================================
    // TOKEN MANAGEMENT
    // =========================================================================

    /**
     * @notice Register a token for bridging
     * @param token The ERC-20 token address
     * @param cantonTokenId The corresponding Canton CIP-56 token ID
     */
    function registerToken(address token, bytes32 cantonTokenId) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) revert InvalidRecipient(token);

        registeredTokens[token] = true;
        cantonTokenIds[token] = cantonTokenId;

        // Get token symbol for event
        string memory symbol;
        try IERC20Metadata(token).symbol() returns (string memory s) {
            symbol = s;
        } catch {
            symbol = "";
        }

        emit TokenRegistered(token, symbol, cantonTokenId, true);
    }

    /**
     * @notice Deregister a token from bridging
     * @param token The ERC-20 token address
     */
    function deregisterToken(address token) external onlyRole(ADMIN_ROLE) {
        registeredTokens[token] = false;
        emit TokenDeregistered(token);
    }

    /**
     * @notice Set rate limit for a token
     * @param token The token address
     * @param maxAmount Maximum amount per period
     * @param period Time period in seconds
     */
    function setTokenRateLimit(
        address token,
        uint256 maxAmount,
        uint256 period
    ) external onlyRole(ADMIN_ROLE) {
        _setRateLimit(token, maxAmount, period);
        emit RateLimitSet(token, maxAmount, period);
    }

    /**
     * @notice Set large withdrawal threshold for a token
     * @param token The token address
     * @param threshold The threshold amount (0 to disable)
     */
    function setLargeWithdrawalThreshold(address token, uint256 threshold) external onlyRole(ADMIN_ROLE) {
        largeWithdrawalThresholds[token] = threshold;
    }

    // =========================================================================
    // ADMINISTRATIVE FUNCTIONS
    // =========================================================================

    /**
     * @notice Pause the bridge
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
        emit BridgePaused(msg.sender);
    }

    /**
     * @notice Unpause the bridge
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
        emit BridgeUnpaused(msg.sender);
    }

    /**
     * @notice Update time lock delay for large withdrawals
     * @param newDelay New delay in seconds
     */
    function setTimeLockDelay(uint256 newDelay) external onlyRole(ADMIN_ROLE) {
        uint256 oldDelay = timeLockDelay;
        timeLockDelay = newDelay;
        emit TimeLockUpdated(oldDelay, newDelay);
    }

    /**
     * @notice Emergency withdrawal of tokens (admin only)
     * @dev Only use in emergencies - breaks bridge invariants
     * @param token The token to withdraw
     * @param amount The amount to withdraw
     * @param recipient The recipient address
     */
    function emergencyWithdraw(
        address token,
        uint256 amount,
        address recipient
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (recipient == address(0)) revert InvalidRecipient(recipient);

        IERC20(token).safeTransfer(recipient, amount);

        // Update locked balance if possible
        if (lockedBalances[token] >= amount) {
            lockedBalances[token] -= amount;
        } else {
            lockedBalances[token] = 0;
        }

        emit EmergencyWithdrawal(token, amount, recipient);
    }

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    /**
     * @inheritdoc ICantonBridge
     */
    function getDepositNonce(address user) external view returns (uint256) {
        return depositNonces[user];
    }

    /**
     * @inheritdoc ICantonBridge
     */
    function isWithdrawalProcessed(bytes32 withdrawalId) external view returns (bool) {
        return processedWithdrawals[withdrawalId];
    }

    /**
     * @inheritdoc ICantonBridge
     */
    function getLockedBalance(address token) external view returns (uint256) {
        return lockedBalances[token];
    }

    /**
     * @inheritdoc ICantonBridge
     */
    function isTokenRegistered(address token) external view returns (bool) {
        return registeredTokens[token];
    }

    /**
     * @notice Get Canton token ID for an EVM token
     * @param token The EVM token address
     * @return The Canton CIP-56 token ID
     */
    function getCantonTokenId(address token) external view returns (bytes32) {
        return cantonTokenIds[token];
    }
}

/**
 * @title IERC20Metadata
 * @notice Minimal interface for ERC20 metadata
 */
interface IERC20Metadata {
    function symbol() external view returns (string memory);
}
