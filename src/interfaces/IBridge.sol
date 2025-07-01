// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IBridge {
    function owner() external view returns (address);
    function grantBridgeTokenRole(address _address) external;
    function bridgeToken(
        address receiverAddress,
        uint64 destinationChainId,
        address tokenToSendAddress,
        uint256 amountToSend,
        address linkTokenAddress,
        address routerAddress
    ) external returns (bool);
}
