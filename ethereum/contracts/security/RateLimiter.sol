// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/**
 * @title RateLimiter
 * @notice Rate limiting functionality for bridge operations
 * @dev Tracks and enforces per-token rate limits within configurable time periods
 */
abstract contract RateLimiter {
    // =========================================================================
    // STRUCTS
    // =========================================================================

    /**
     * @notice Rate limit configuration and state for a token
     * @param maxAmount Maximum amount allowed per period
     * @param period Time period in seconds
     * @param lastReset Timestamp of last period reset
     * @param usedAmount Amount used in current period
     */
    struct RateLimit {
        uint256 maxAmount;
        uint256 period;
        uint256 lastReset;
        uint256 usedAmount;
    }

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice Rate limits per token address
    mapping(address => RateLimit) internal _rateLimits;

    // =========================================================================
    // EVENTS
    // =========================================================================

    /**
     * @notice Emitted when a rate limit is configured
     * @param token The token address
     * @param maxAmount Maximum amount per period
     * @param period Time period in seconds
     */
    event RateLimitConfigured(address indexed token, uint256 maxAmount, uint256 period);

    /**
     * @notice Emitted when rate limit is removed
     * @param token The token address
     */
    event RateLimitRemoved(address indexed token);

    // =========================================================================
    // ERRORS
    // =========================================================================

    /// @notice Thrown when rate limit is exceeded
    error RateLimitExceeded(address token, uint256 requested, uint256 available);

    /// @notice Thrown when rate limit period is invalid
    error InvalidRateLimitPeriod();

    // =========================================================================
    // INTERNAL FUNCTIONS
    // =========================================================================

    /**
     * @notice Set rate limit for a token
     * @param token The token address
     * @param maxAmount Maximum amount per period (0 to disable)
     * @param period Time period in seconds
     */
    function _setRateLimit(address token, uint256 maxAmount, uint256 period) internal {
        if (maxAmount > 0 && period == 0) {
            revert InvalidRateLimitPeriod();
        }

        _rateLimits[token] = RateLimit({
            maxAmount: maxAmount,
            period: period,
            lastReset: block.timestamp,
            usedAmount: 0
        });

        emit RateLimitConfigured(token, maxAmount, period);
    }

    /**
     * @notice Remove rate limit for a token
     * @param token The token address
     */
    function _removeRateLimit(address token) internal {
        delete _rateLimits[token];
        emit RateLimitRemoved(token);
    }

    /**
     * @notice Check and update rate limit for a transfer
     * @dev Reverts if rate limit is exceeded
     * @param token The token address
     * @param amount The amount to transfer
     */
    function _checkAndUpdateRateLimit(address token, uint256 amount) internal {
        RateLimit storage limit = _rateLimits[token];

        // If no limit is set (maxAmount == 0), allow unlimited transfers
        if (limit.maxAmount == 0) {
            return;
        }

        // Reset period if needed
        if (block.timestamp >= limit.lastReset + limit.period) {
            limit.lastReset = block.timestamp;
            limit.usedAmount = 0;
        }

        // Calculate available amount
        uint256 available = limit.maxAmount - limit.usedAmount;

        // Check if transfer exceeds limit
        if (amount > available) {
            revert RateLimitExceeded(token, amount, available);
        }

        // Update used amount
        limit.usedAmount += amount;
    }

    /**
     * @notice Check rate limit without updating (view only)
     * @param token The token address
     * @param amount The amount to check
     * @return allowed Whether the amount would be allowed
     * @return available The remaining available amount
     */
    function _checkRateLimit(
        address token,
        uint256 amount
    ) internal view returns (bool allowed, uint256 available) {
        RateLimit storage limit = _rateLimits[token];

        // If no limit is set, allow unlimited
        if (limit.maxAmount == 0) {
            return (true, type(uint256).max);
        }

        // Check if period has reset
        if (block.timestamp >= limit.lastReset + limit.period) {
            available = limit.maxAmount;
        } else {
            available = limit.maxAmount - limit.usedAmount;
        }

        allowed = amount <= available;
    }

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    /**
     * @notice Get the rate limit configuration for a token
     * @param token The token address
     * @return maxAmount Maximum amount per period
     * @return period Time period in seconds
     * @return lastReset Last reset timestamp
     * @return usedAmount Amount used in current period
     */
    function getRateLimit(
        address token
    )
        public
        view
        returns (uint256 maxAmount, uint256 period, uint256 lastReset, uint256 usedAmount)
    {
        RateLimit storage limit = _rateLimits[token];
        return (limit.maxAmount, limit.period, limit.lastReset, limit.usedAmount);
    }

    /**
     * @notice Get the remaining rate limit for a token
     * @param token The token address
     * @return remaining The remaining amount that can be transferred
     */
    function getRemainingRateLimit(address token) public view returns (uint256 remaining) {
        RateLimit storage limit = _rateLimits[token];

        // If no limit is set, return max uint256
        if (limit.maxAmount == 0) {
            return type(uint256).max;
        }

        // If period has reset, return full amount
        if (block.timestamp >= limit.lastReset + limit.period) {
            return limit.maxAmount;
        }

        // Otherwise return remaining
        return limit.maxAmount - limit.usedAmount;
    }

    /**
     * @notice Check when the rate limit period resets
     * @param token The token address
     * @return resetTime The timestamp when the period resets (0 if no limit)
     */
    function getRateLimitResetTime(address token) public view returns (uint256 resetTime) {
        RateLimit storage limit = _rateLimits[token];

        if (limit.maxAmount == 0) {
            return 0;
        }

        return limit.lastReset + limit.period;
    }
}
