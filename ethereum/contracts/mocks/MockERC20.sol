// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @notice Mock ERC-20 token for testing
 * @dev Allows minting tokens for test purposes
 */
contract MockERC20 is ERC20 {
    uint8 private immutable _decimals;

    /**
     * @notice Create a mock ERC-20 token
     * @param name Token name
     * @param symbol Token symbol
     * @param decimals_ Token decimals
     */
    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    /**
     * @notice Get token decimals
     * @return The number of decimals
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Mint tokens to an address
     * @param to The recipient address
     * @param amount The amount to mint
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from the caller
     * @param amount The amount to burn
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

/**
 * @title MockUSDC
 * @notice Mock USDC token for testing (6 decimals)
 */
contract MockUSDC is MockERC20 {
    constructor() MockERC20("USD Coin", "USDC", 6) {}
}

/**
 * @title MockWBTC
 * @notice Mock WBTC token for testing (8 decimals)
 */
contract MockWBTC is MockERC20 {
    constructor() MockERC20("Wrapped BTC", "WBTC", 8) {}
}

/**
 * @title MockPROMPT
 * @notice Mock PROMPT token for testing (18 decimals)
 */
contract MockPROMPT is MockERC20 {
    constructor() MockERC20("Wayfinder PROMPT", "PROMPT", 18) {}
}
