// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRebaseTokenPool {
    function deposit() external payable;
    function redeem(uint256 amount) external;
}
