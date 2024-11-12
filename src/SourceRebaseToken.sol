// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {RebaseTokenBase} from "./RebaseTokenBase.sol";

// NOTE: name, symbol, decimals need to be included
contract SourceRebaseToken is RebaseTokenBase {
    address public s_vault;

    event AccumulatedRateUpdated(uint256 index, uint256 timestamp);
    event VaultAndPoolSet(address vault, address pool);

    error RebaseToken__SenderNotVault(address sender);
    error RebaseToken__SenderNotPoolOrVault(address sender);

    constructor() RebaseTokenBase() {}

    modifier onlyVault() {
        if (msg.sender != s_vault) {
            revert RebaseToken__SenderNotVault(msg.sender);
        }
        _;
    }

    modifier onlyPoolOrVault() {
        if (msg.sender != s_pool && msg.sender != s_vault) {
            revert RebaseToken__SenderNotPoolOrVault(msg.sender);
        }
        _;
    }

    function setVaultAndPool(address vault, address pool) external onlyOwner {
        s_vault = vault;
        s_pool = pool;
        emit VaultAndPoolSet(vault, pool);
    }

    // NOTE: is there a way to have this in the base but apply different modifiers
    /// @notice Mints new tokens for a given address.
    /// @param account The address to mint the new tokens to.
    /// @param amount The number of tokens to be minted.
    /// @dev this function increases the total supply.
    function mint(address account, uint256 amount) external onlyPoolOrVault {
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
    function burn(address account, uint256 amount) external onlyPoolOrVault {
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

    // /**
    //  * @dev calculates the linear interest factor
    //  * @return the linear interest factor
    //  *
    //  */
    // function _calculateLinearInterest() internal view returns (uint256) {
    //     uint256 timeDifference = block.timestamp - s_lastUpdatedTimestamp;
    //     // Calculate the linear interest factor over the elapsed time
    //     return (s_interestRate * timeDifference + PRECISION_FACTOR);
    // }

    /**
     * @dev updates the interest rate
     * @param _interestRate the new interest rate
     *
     */
    function updateInterestRate(uint256 _interestRate) external onlyOwner {
        _updateAccumulatedRate();
        s_interestRate = _interestRate;
    }

    /**
     * @dev updates the accumulated rate and the last updated timestamp
     * @notice this function should be called every time the interest rate changes
     *
     */
    function _updateAccumulatedRate() internal {
        // Calculate the updated cumulative index
        s_accumulatedRate = _calculateAccumulatedInterest();
        s_lastUpdatedTimestamp = block.timestamp;
        // NOTE: send a cross-chain message! Implements as before:) only data no tokens
        // _sendMessagePayLINK()
        emit AccumulatedRateUpdated(s_accumulatedRate, s_lastUpdatedTimestamp);
    }
}
