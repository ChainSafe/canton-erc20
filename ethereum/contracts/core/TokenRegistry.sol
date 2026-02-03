// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IBridgeEvents} from "../interfaces/IBridgeEvents.sol";

/**
 * @title TokenRegistry
 * @notice Registry for managing bridgeable tokens
 * @dev Maintains metadata and mappings for ERC-20 <-> CIP-56 token pairs
 */
contract TokenRegistry is AccessControl, IBridgeEvents {
    // =========================================================================
    // STRUCTS
    // =========================================================================

    /**
     * @notice Token information structure
     * @param symbol Token symbol
     * @param name Token name
     * @param decimals Token decimals
     * @param isNative True if this is the native version on this chain
     * @param isActive True if token is active for bridging
     * @param cantonTokenId The corresponding Canton CIP-56 token identifier
     * @param chainId The EVM chain ID where this token exists
     */
    struct TokenInfo {
        string symbol;
        string name;
        uint8 decimals;
        bool isNative;
        bool isActive;
        bytes32 cantonTokenId;
        uint256 chainId;
    }

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    /// @notice Role for registering tokens
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice Token information by address
    mapping(address => TokenInfo) public tokens;

    /// @notice List of all registered token addresses
    address[] public tokenList;

    /// @notice Mapping from Canton token ID to EVM token address
    mapping(bytes32 => address) public cantonToEvmToken;

    /// @notice Supported chain IDs
    mapping(uint256 => bool) public supportedChains;

    /// @notice List of supported chain IDs
    uint256[] public supportedChainList;

    // =========================================================================
    // ERRORS
    // =========================================================================

    /// @notice Thrown when token is already registered
    error TokenAlreadyRegistered(address token);

    /// @notice Thrown when token is not registered
    error TokenNotRegistered(address token);

    /// @notice Thrown when token address is invalid
    error InvalidTokenAddress();

    /// @notice Thrown when chain is not supported
    error ChainNotSupported(uint256 chainId);

    /// @notice Thrown when Canton token ID is already mapped
    error CantonTokenAlreadyMapped(bytes32 cantonTokenId);

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    /**
     * @notice Initialize the token registry
     * @param admin The initial admin address
     */
    constructor(address admin) {
        if (admin == address(0)) revert InvalidTokenAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);

        // Add current chain as supported
        supportedChains[block.chainid] = true;
        supportedChainList.push(block.chainid);
    }

    // =========================================================================
    // TOKEN REGISTRATION
    // =========================================================================

    /**
     * @notice Register a new token for bridging
     * @param token The ERC-20 token address
     * @param cantonTokenId The corresponding Canton CIP-56 token ID
     * @param isNative True if this is the native token (vs wrapped)
     */
    function registerToken(
        address token,
        bytes32 cantonTokenId,
        bool isNative
    ) external onlyRole(REGISTRAR_ROLE) {
        if (token == address(0)) revert InvalidTokenAddress();
        if (tokens[token].isActive) revert TokenAlreadyRegistered(token);
        if (cantonToEvmToken[cantonTokenId] != address(0)) {
            revert CantonTokenAlreadyMapped(cantonTokenId);
        }

        // Fetch metadata from token contract
        string memory symbol;
        string memory name;
        uint8 decimals;

        try IERC20Metadata(token).symbol() returns (string memory s) {
            symbol = s;
        } catch {
            symbol = "";
        }

        try IERC20Metadata(token).name() returns (string memory n) {
            name = n;
        } catch {
            name = "";
        }

        try IERC20Metadata(token).decimals() returns (uint8 d) {
            decimals = d;
        } catch {
            decimals = 18;
        }

        tokens[token] = TokenInfo({
            symbol: symbol,
            name: name,
            decimals: decimals,
            isNative: isNative,
            isActive: true,
            cantonTokenId: cantonTokenId,
            chainId: block.chainid
        });

        tokenList.push(token);
        cantonToEvmToken[cantonTokenId] = token;

        emit TokenRegistered(token, symbol, cantonTokenId, isNative);
    }

    /**
     * @notice Register a token with explicit metadata
     * @param token The ERC-20 token address
     * @param symbol Token symbol
     * @param name Token name
     * @param decimals Token decimals
     * @param cantonTokenId The corresponding Canton CIP-56 token ID
     * @param isNative True if this is the native token
     */
    function registerTokenWithMetadata(
        address token,
        string calldata symbol,
        string calldata name,
        uint8 decimals,
        bytes32 cantonTokenId,
        bool isNative
    ) external onlyRole(REGISTRAR_ROLE) {
        if (token == address(0)) revert InvalidTokenAddress();
        if (tokens[token].isActive) revert TokenAlreadyRegistered(token);
        if (cantonToEvmToken[cantonTokenId] != address(0)) {
            revert CantonTokenAlreadyMapped(cantonTokenId);
        }

        tokens[token] = TokenInfo({
            symbol: symbol,
            name: name,
            decimals: decimals,
            isNative: isNative,
            isActive: true,
            cantonTokenId: cantonTokenId,
            chainId: block.chainid
        });

        tokenList.push(token);
        cantonToEvmToken[cantonTokenId] = token;

        emit TokenRegistered(token, symbol, cantonTokenId, isNative);
    }

    /**
     * @notice Deactivate a token
     * @param token The token address
     */
    function deactivateToken(address token) external onlyRole(REGISTRAR_ROLE) {
        if (!tokens[token].isActive) revert TokenNotRegistered(token);

        tokens[token].isActive = false;
        emit TokenDeregistered(token);
    }

    /**
     * @notice Reactivate a token
     * @param token The token address
     */
    function reactivateToken(address token) external onlyRole(REGISTRAR_ROLE) {
        if (tokens[token].chainId == 0) revert TokenNotRegistered(token);

        tokens[token].isActive = true;
        emit TokenUpdated(token);
    }

    /**
     * @notice Update Canton token ID mapping
     * @param token The EVM token address
     * @param newCantonTokenId The new Canton token ID
     */
    function updateCantonTokenId(
        address token,
        bytes32 newCantonTokenId
    ) external onlyRole(REGISTRAR_ROLE) {
        if (tokens[token].chainId == 0) revert TokenNotRegistered(token);

        bytes32 oldCantonId = tokens[token].cantonTokenId;
        delete cantonToEvmToken[oldCantonId];

        tokens[token].cantonTokenId = newCantonTokenId;
        cantonToEvmToken[newCantonTokenId] = token;

        emit TokenUpdated(token);
    }

    // =========================================================================
    // CHAIN MANAGEMENT
    // =========================================================================

    /**
     * @notice Add a supported chain
     * @param chainId The chain ID to add
     */
    function addSupportedChain(uint256 chainId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!supportedChains[chainId]) {
            supportedChains[chainId] = true;
            supportedChainList.push(chainId);
        }
    }

    /**
     * @notice Remove a supported chain
     * @param chainId The chain ID to remove
     */
    function removeSupportedChain(uint256 chainId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        supportedChains[chainId] = false;
        // Note: We don't remove from array to preserve indices
    }

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    /**
     * @notice Get token information
     * @param token The token address
     * @return info The token information struct
     */
    function getTokenInfo(address token) external view returns (TokenInfo memory info) {
        return tokens[token];
    }

    /**
     * @notice Check if a token is active
     * @param token The token address
     * @return True if token is active
     */
    function isTokenActive(address token) external view returns (bool) {
        return tokens[token].isActive;
    }

    /**
     * @notice Get EVM token address from Canton token ID
     * @param cantonTokenId The Canton CIP-56 token ID
     * @return The EVM token address
     */
    function getEvmToken(bytes32 cantonTokenId) external view returns (address) {
        return cantonToEvmToken[cantonTokenId];
    }

    /**
     * @notice Get Canton token ID from EVM token address
     * @param token The EVM token address
     * @return The Canton CIP-56 token ID
     */
    function getCantonTokenId(address token) external view returns (bytes32) {
        return tokens[token].cantonTokenId;
    }

    /**
     * @notice Get the total number of registered tokens
     * @return The count of registered tokens
     */
    function getTokenCount() external view returns (uint256) {
        return tokenList.length;
    }

    /**
     * @notice Get all registered token addresses
     * @return Array of token addresses
     */
    function getAllTokens() external view returns (address[] memory) {
        return tokenList;
    }

    /**
     * @notice Get all active token addresses
     * @return Array of active token addresses
     */
    function getActiveTokens() external view returns (address[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < tokenList.length; i++) {
            if (tokens[tokenList[i]].isActive) {
                activeCount++;
            }
        }

        address[] memory activeTokens = new address[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < tokenList.length; i++) {
            if (tokens[tokenList[i]].isActive) {
                activeTokens[index] = tokenList[i];
                index++;
            }
        }

        return activeTokens;
    }

    /**
     * @notice Check if a chain is supported
     * @param chainId The chain ID to check
     * @return True if chain is supported
     */
    function isChainSupported(uint256 chainId) external view returns (bool) {
        return supportedChains[chainId];
    }

    /**
     * @notice Get all supported chain IDs
     * @return Array of supported chain IDs
     */
    function getSupportedChains() external view returns (uint256[] memory) {
        return supportedChainList;
    }
}
