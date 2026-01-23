// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/**
 * @title IBridgeEvents
 * @notice Administrative and operational events for the Canton Bridge
 */
interface IBridgeEvents {
    // =========================================================================
    // TOKEN REGISTRY EVENTS
    // =========================================================================

    /**
     * @notice Emitted when a token is registered for bridging
     * @param token The ERC-20 token address
     * @param symbol The token symbol
     * @param cantonTokenId The corresponding Canton CIP-56 token identifier
     * @param isNative True if this is the native version (vs wrapped)
     */
    event TokenRegistered(
        address indexed token,
        string symbol,
        bytes32 indexed cantonTokenId,
        bool isNative
    );

    /**
     * @notice Emitted when a token is deregistered
     * @param token The ERC-20 token address
     */
    event TokenDeregistered(address indexed token);

    /**
     * @notice Emitted when token information is updated
     * @param token The ERC-20 token address
     */
    event TokenUpdated(address indexed token);

    // =========================================================================
    // ADMINISTRATIVE EVENTS
    // =========================================================================

    /**
     * @notice Emitted when the bridge is paused
     * @param by The address that paused the bridge
     */
    event BridgePaused(address indexed by);

    /**
     * @notice Emitted when the bridge is unpaused
     * @param by The address that unpaused the bridge
     */
    event BridgeUnpaused(address indexed by);

    /**
     * @notice Emitted when a relayer is updated
     * @param oldRelayer The previous relayer address
     * @param newRelayer The new relayer address
     */
    event RelayerUpdated(address indexed oldRelayer, address indexed newRelayer);

    /**
     * @notice Emitted when the time lock delay is updated
     * @param oldDelay The previous delay in seconds
     * @param newDelay The new delay in seconds
     */
    event TimeLockUpdated(uint256 oldDelay, uint256 newDelay);

    // =========================================================================
    // RATE LIMIT EVENTS
    // =========================================================================

    /**
     * @notice Emitted when a rate limit is set or updated
     * @param token The token address
     * @param amount Maximum amount per period
     * @param period Time period in seconds
     */
    event RateLimitSet(address indexed token, uint256 amount, uint256 period);

    // =========================================================================
    // SECURITY EVENTS
    // =========================================================================

    /**
     * @notice Emitted when emergency withdrawal is triggered
     * @param token The token address
     * @param amount The amount withdrawn
     * @param recipient The recipient address
     */
    event EmergencyWithdrawal(address indexed token, uint256 amount, address indexed recipient);

    /**
     * @notice Emitted when a large withdrawal is queued (time-locked)
     * @param withdrawalId The withdrawal identifier
     * @param token The token address
     * @param amount The amount
     * @param executeAfter The timestamp after which it can be executed
     */
    event LargeWithdrawalQueued(
        bytes32 indexed withdrawalId,
        address indexed token,
        uint256 amount,
        uint256 executeAfter
    );

    /**
     * @notice Emitted when a large withdrawal is cancelled by admin
     * @param withdrawalId The withdrawal identifier
     */
    event LargeWithdrawalCancelled(bytes32 indexed withdrawalId);
}
