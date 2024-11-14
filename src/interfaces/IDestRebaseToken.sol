// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IDestRebaseToken {
    function setRates(uint256 newAccumulatedRate, uint256 newInterestRate) external;
    function mint(address to, uint256 amount, uint256 userAccumulatedRate) external;
}
