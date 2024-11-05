// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IRebaseToken {
    function burn(uint256 amount) external;
    function mint(address to, uint256 amount) external;
    function getUserInfo(address user) external view returns (uint256, uint256, uint40);
    function setUserInfo(address user, uint256 userIndex, uint256 accumulatedRate, uint40 lastDepositTime) external;
}
