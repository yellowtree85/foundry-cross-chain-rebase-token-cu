// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RebaseTokenBase} from "./RebaseTokenBase.sol";

contract DestRebaseToken is RebaseTokenBase {
    event PoolSet(address pool);

    constructor() RebaseTokenBase() {}

    modifier onlyPool() {
        if (msg.sender != s_pool) {
            revert RebaseToken__SenderNotPool(s_pool, msg.sender);
        }
        _;
    }

    /**
     * @dev sets the pool address after deployment. This is needed to ensure that only the pool can mint and burn tokens.
     * @param pool the address of the pool
     */
    function setPool(address pool) external onlyOwner {
        s_pool = pool;
        emit PoolSet(pool);
    }

    function mint(address to, uint256 amount, uint256 interestRate) public override onlyPool {
        super.mint(to, amount, interestRate);
    }

    function burn(address from, uint256 amount) public override onlyPool {
        super.burn(from, amount);
    }
}
