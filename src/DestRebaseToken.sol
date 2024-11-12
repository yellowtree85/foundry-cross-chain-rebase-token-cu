// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {RebaseTokenBase} from "./RebaseTokenBase.sol";

// NOTE: name, symbol, decimals need to be included
contract DestRebaseToken is RebaseTokenBase {
    event UserInfoUpdated(address indexed user, uint256 index);
    event PoolSet(address pool);

    constructor() RebaseTokenBase() {}

    function setPool(address pool) external onlyOwner {
        s_pool = pool;
        emit PoolSet(pool);
    }

    function setUserIndex(address user, uint256 index) external onlyPool {
        userIndexes[user] = index;
        emit UserInfoUpdated(user, index);
    }

    // NOTE: is there a way to have this in the base but apply different modifiers
    /// @notice Mints new tokens for a given address.
    /// @param account The address to mint the new tokens to.
    /// @param amount The number of tokens to be minted.
    /// @dev this function increases the total supply.
    function mint(address account, uint256 amount) external onlyPool {
        // NOTE: should I have a check for zero?
        // accumulates the balance of the user
        _beforeUpdate(address(0), account, amount);
        _mint(account, amount);
    }

    /// @notice Burns tokens from the sender.
    /// @param amount The number of tokens to be burned.
    /// @dev this function decreases the total supply.
    function burn(address account, uint256 amount) external onlyPool {
        // NOTE: should I have a check for zero?
        // accumulates the balance of the user
        _beforeUpdate(account, address(0), amount);
        _burn(account, amount);
    }
}
