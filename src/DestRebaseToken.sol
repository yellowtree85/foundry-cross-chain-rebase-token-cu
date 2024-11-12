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
        if (amount == 0) {
            revert RebaseToken__CannotTransferZero();
        }

        // accumulates the balance of the user
        (, uint256 currentBalance, uint256 balanceIncrease, uint256 index) = _applyAccruedInterest(account);

        // mints tokens equivalent to the amount requested
        // events are emitted in the internal function
        _mint(account, amount);

        emit Mint(account, amount, currentBalance + amount, index);
    }

    /// @notice Burns tokens from the sender.
    /// @param amount The number of tokens to be burned.
    /// @dev this function decreases the total supply.
    function burn(address account, uint256 amount) external onlyPool {
        if (amount == 0) {
            revert RebaseToken__CannotTransferZero();
        }

        // accumulates the balance of the user
        (, uint256 currentBalance, uint256 balanceIncrease, uint256 index) = _applyAccruedInterest(account);

        //if amount is equal to uint(-1), the user wants to redeem everything
        if (amount == UINT_MAX_VALUE) {
            amount = currentBalance;
        }

        if (amount > currentBalance) {
            revert RebaseToken__AmountGreaterThanBalance(amount, currentBalance);
        }

        // burns tokens equivalent to the amount requested
        _burn(account, amount);

        //reset the user data if the remaining balance is 0
        if (currentBalance - amount == 0) {
            userIndexes[account] = 0;
        }

        emit Burn(account, amount, currentBalance - amount, index);
    }
}
