// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IDestRebaseToken {
    function setRates(uint256 newAccumulatedRate, uint256 newInterestRate) external;
}
