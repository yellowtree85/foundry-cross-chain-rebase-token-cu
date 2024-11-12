// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IRebaseToken {
    function burn(address from, uint256 amount) external;
    function mint(address to, uint256 amount) external;
    function getUserIndex(address user) external view returns (uint256);
    function setUserIndex(address user, uint256 newIndex) external;
}
