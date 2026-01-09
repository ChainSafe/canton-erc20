// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {CantonBridge} from "../contracts/core/CantonBridge.sol";
import {TokenRegistry} from "../contracts/core/TokenRegistry.sol";

/**
 * @title DeployCantonBridge
 * @notice Deployment script for Canton Bridge contracts
 */
contract DeployCantonBridge is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address admin = vm.envOr("ADMIN_ADDRESS", deployer);
        address relayer = vm.envOr("RELAYER_ADDRESS", deployer);

        console2.log("Deploying Canton Bridge contracts...");
        console2.log("Deployer:", deployer);
        console2.log("Admin:", admin);
        console2.log("Relayer:", relayer);
        console2.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Token Registry
        TokenRegistry registry = new TokenRegistry(admin);
        console2.log("TokenRegistry deployed at:", address(registry));

        // Deploy Canton Bridge
        CantonBridge bridge = new CantonBridge(admin);
        console2.log("CantonBridge deployed at:", address(bridge));

        // Grant relayer role
        bridge.grantRole(bridge.RELAYER_ROLE(), relayer);
        console2.log("Relayer role granted to:", relayer);

        vm.stopBroadcast();

        console2.log("\nDeployment complete!");
        console2.log("===================");
        console2.log("TokenRegistry:", address(registry));
        console2.log("CantonBridge:", address(bridge));
    }
}

/**
 * @title RegisterToken
 * @notice Script to register a token for bridging
 */
contract RegisterToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address bridgeAddress = vm.envAddress("BRIDGE_ADDRESS");
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        bytes32 cantonTokenId = vm.envBytes32("CANTON_TOKEN_ID");

        console2.log("Registering token...");
        console2.log("Bridge:", bridgeAddress);
        console2.log("Token:", tokenAddress);

        vm.startBroadcast(deployerPrivateKey);

        CantonBridge bridge = CantonBridge(bridgeAddress);
        bridge.registerToken(tokenAddress, cantonTokenId);

        vm.stopBroadcast();

        console2.log("Token registered successfully!");
    }
}

/**
 * @title SetRateLimit
 * @notice Script to set rate limit for a token
 */
contract SetRateLimit is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address bridgeAddress = vm.envAddress("BRIDGE_ADDRESS");
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        uint256 maxAmount = vm.envUint("MAX_AMOUNT");
        uint256 period = vm.envUint("PERIOD");

        console2.log("Setting rate limit...");
        console2.log("Bridge:", bridgeAddress);
        console2.log("Token:", tokenAddress);
        console2.log("Max Amount:", maxAmount);
        console2.log("Period:", period);

        vm.startBroadcast(deployerPrivateKey);

        CantonBridge bridge = CantonBridge(bridgeAddress);
        bridge.setTokenRateLimit(tokenAddress, maxAmount, period);

        vm.stopBroadcast();

        console2.log("Rate limit set successfully!");
    }
}
