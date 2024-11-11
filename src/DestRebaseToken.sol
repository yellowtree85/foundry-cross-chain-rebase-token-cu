// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {RebaseTokenBase} from "./RebaseTokenBase.sol";

// NOTE: name, symbol, decimals need to be included
contract DestRebaseToken is RebaseTokenBase {
    event UserInfoUpdated(address indexed user, uint256 index, uint256 rate, uint256 timestamp);
    event PoolSet(address pool);

    constructor() RebaseTokenBase() {}

    function setPool(address pool) external onlyOwner {
        s_pool = pool;
        emit PoolSet(pool);
    }

    function setUserInfo(address user, uint256 index, uint256 rate, uint256 timestamp) external onlyPool {
        userIndexes[user] = index;
        s_accumulatedRate = rate;
        s_lastUpdatedTimestamp = timestamp;
        emit UserInfoUpdated(user, index, rate, timestamp);
    }
}
