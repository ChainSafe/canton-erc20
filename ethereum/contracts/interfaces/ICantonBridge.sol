// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/**
 * @title ICantonBridge
 * @notice Interface for the Canton Network ERC-20 bridge
 * @dev Defines the core functions for depositing to Canton and withdrawing from Canton
 */
interface ICantonBridge {
    // =========================================================================
    // EVENTS
    // =========================================================================

    /**
     * @notice Emitted when tokens are deposited to Canton
     * @param token The ERC-20 token address
     * @param sender The address that initiated the deposit
     * @param amount The amount of tokens deposited
     * @param cantonRecipient The Canton fingerprint of the recipient (32 bytes)
     * @param nonce The deposit nonce for this sender
     */
    event DepositToCanton(
        address indexed token,
        address indexed sender,
        uint256 amount,
        bytes32 indexed cantonRecipient,
        uint256 nonce
    );

    /**
     * @notice Emitted when tokens are withdrawn from Canton to EVM
     * @param token The ERC-20 token address
     * @param recipient The EVM address receiving the tokens
     * @param amount The amount of tokens withdrawn
     * @param cantonSender The Canton fingerprint of the sender
     * @param withdrawalId Unique identifier for this withdrawal
     */
    event WithdrawalFromCanton(
        address indexed token,
        address indexed recipient,
        uint256 amount,
        bytes32 indexed cantonSender,
        bytes32 withdrawalId
    );

    /**
     * @notice Emitted when a withdrawal is processed
     * @param withdrawalId The unique withdrawal identifier
     * @param success Whether the withdrawal succeeded
     */
    event WithdrawalProcessed(bytes32 indexed withdrawalId, bool success);

    // =========================================================================
    // ERRORS
    // =========================================================================

    /// @notice Thrown when the token is not registered for bridging
    error TokenNotRegistered(address token);

    /// @notice Thrown when the amount is zero or invalid
    error InvalidAmount();

    /// @notice Thrown when the fingerprint is invalid
    error InvalidFingerprint(bytes32 fingerprint);

    /// @notice Thrown when the recipient address is invalid
    error InvalidRecipient(address recipient);

    /// @notice Thrown when a withdrawal has already been processed
    error WithdrawalAlreadyProcessed(bytes32 withdrawalId);

    /// @notice Thrown when the withdrawal proof is invalid
    error InvalidWithdrawalProof();

    /// @notice Thrown when there's insufficient locked balance
    error InsufficientLockedBalance(address token, uint256 requested, uint256 available);

    // =========================================================================
    // CORE FUNCTIONS
    // =========================================================================

    /**
     * @notice Deposit ERC-20 tokens to bridge them to Canton Network
     * @dev Locks tokens in the bridge and emits DepositToCanton event for middleware
     * @param token The ERC-20 token to deposit
     * @param amount The amount of tokens to deposit
     * @param cantonRecipient The Canton fingerprint of the recipient (32 bytes)
     * @return nonce The deposit nonce for tracking
     */
    function depositToCanton(
        address token,
        uint256 amount,
        bytes32 cantonRecipient
    ) external returns (uint256 nonce);

    /**
     * @notice Withdraw tokens from Canton back to EVM
     * @dev Called by relayer after Canton burn is confirmed
     * @param token The ERC-20 token to withdraw
     * @param amount The amount of tokens to withdraw
     * @param recipient The EVM address to receive the tokens
     * @param withdrawalId Unique identifier for this withdrawal
     * @param proof Cryptographic proof from Canton middleware
     */
    function withdrawFromCanton(
        address token,
        uint256 amount,
        address recipient,
        bytes32 withdrawalId,
        bytes calldata proof
    ) external;

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    /**
     * @notice Get the deposit nonce for a user
     * @param user The user address
     * @return The current nonce
     */
    function getDepositNonce(address user) external view returns (uint256);

    /**
     * @notice Check if a withdrawal has been processed
     * @param withdrawalId The withdrawal identifier
     * @return True if already processed
     */
    function isWithdrawalProcessed(bytes32 withdrawalId) external view returns (bool);

    /**
     * @notice Get the locked balance for a token
     * @param token The token address
     * @return The amount of tokens locked in the bridge
     */
    function getLockedBalance(address token) external view returns (uint256);

    /**
     * @notice Check if a token is registered for bridging
     * @param token The token address
     * @return True if registered
     */
    function isTokenRegistered(address token) external view returns (bool);
}
