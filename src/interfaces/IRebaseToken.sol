// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IRebaseToken {
    function burn(address from, uint256 amount) external;
    function mint(address to, uint256 amount) external;
    function getInterestRate() external view returns (uint256);
    function setUserInterestRate(address user, uint256 newInterestRate) external;
    function getUserInterestRate(address user) external view returns (uint256);
}
