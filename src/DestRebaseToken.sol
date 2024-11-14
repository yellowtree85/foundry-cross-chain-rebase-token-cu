// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@ccip/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@ccip/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";

import {RebaseTokenBase} from "./RebaseTokenBase.sol";

// NOTE: name, symbol, decimals need to be included
contract DestRebaseToken is RebaseTokenBase, CCIPReceiver {
    event UserInfoUpdated(address indexed user, uint256 index);
    event PoolSet(address pool);
    event RatesUpdated(uint256 newAccumulatedRate, uint256 newInterestRate, uint256 newLastUpdatedTimestamp);
    event MessageReceived(bytes32 messageId, uint64 sourceChainSelector, address sender, bytes data);

    error RebaseToken__SenderNotPool(address pool, address sender);
    error RebaseToken__SenderNotThisAddress(address thisAddress, address sender);
    error RebaseToken__RecieveFailed();
    error RebaseToken__NoReturnDataExpected();

    constructor(address router) RebaseTokenBase() CCIPReceiver(router) {}

    modifier onlyPool() {
        if (msg.sender != s_pool) {
            revert RebaseToken__SenderNotPool(s_pool, msg.sender);
        }
        _;
    }

    modifier onlySelf() {
        if (msg.sender != address(this)) {
            revert RebaseToken__SenderNotThisAddress(address(this), msg.sender);
        }
        _;
    }

    function setPool(address pool) external onlyOwner {
        s_pool = pool;
        emit PoolSet(pool);
    }

    function setUserAccumulatedRate(address user, uint256 userAccumulatedRate) external onlyPool {
        s_userAccumulatedRates[user] = userAccumulatedRate;
        emit UserInfoUpdated(user, userAccumulatedRate);
    }

    function setRates(uint256 newAccumulatedRate, uint256 newInterestRate) external onlySelf {
        s_accumulatedInterest = newAccumulatedRate;
        s_interestRate = newInterestRate;
        s_lastUpdatedTimestamp = block.timestamp;
        emit RatesUpdated(newAccumulatedRate, newInterestRate, block.timestamp);
    }

    // NOTE: is there a way to have this in the base but apply different modifiers
    /// @notice Mints new tokens for a given address.
    /// @param account The address to mint the new tokens to.
    /// @param amount The number of tokens to be minted.
    /// @param sentAccumulatedInterest The user's accumulated interest when their minted tokens were last updated on the source chain.
    /// @dev this function increases the total supply.
    function mint(address account, uint256 amount, uint256 sentAccumulatedInterest) external onlyPool {
        // Only called by the pool when someone bridges
        // accumulates the balance of the user
        // also sets the user's accumulated rate
        _beforeUpdate(address(0), account, amount);
        // calculates the interest accrued since they initiated the cross-chain transfer on the amount they bridged
        if (sentAccumulatedInterest < _calculateAccumulatedInterestSinceLastUpdate()) {
            uint256 amountExtra =
                amount - (amount * _calculateAccumulatedInterestSinceLastUpdate() / sentAccumulatedInterest);
        }

        _mint(account, amount);
    }

    /// @notice Burns tokens from the sender.
    /// @param amount The number of tokens to be burned.
    /// @dev this function decreases the total supply.
    function burn(address account, uint256 amount) external onlyPool {
        // only called by the pool when someone bridges
        // accumulates the balance of the user
        _beforeUpdate(account, address(0), amount);
        _burn(account, amount);
    }

    /// @notice Receives a CCIP message and processes it.
    /// @param any2EvmMessage The received CCIP message.
    /// @dev This function is called by the CCIP router when a rebase event happens on the source chain.
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        // NOTE: gievn that it is a function call on this contract, should it not be an external call?
        /* solhint-disable avoid-low-level-calls */
        (bool success, bytes memory returnData) = address(this).call(any2EvmMessage.data); // low level call to the token contract using the encoded function selector and arguments

        if (!success) revert RebaseToken__RecieveFailed();
        if (returnData.length > 0) revert RebaseToken__NoReturnDataExpected();

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
            any2EvmMessage.data // received data
        );
    }
}
