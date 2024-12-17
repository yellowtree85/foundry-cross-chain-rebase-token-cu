// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";

contract BridgeTokensScript is Script {
    function createCCIPMessage(
        address receiverAddress,
        address tokenToSendAddress,
        uint256 amountToSend,
        address linkTokenAddress
    ) public pure returns (Client.EVM2AnyMessage memory) {
        // 1. Create the token struct array
        Client.EVMTokenAmount[] memory tokenToSendDetails = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount =
            Client.EVMTokenAmount({token: tokenToSendAddress, amount: amountToSend});
        tokenToSendDetails[0] = tokenAmount;
        // 3. Create the message struct with no data and the designated amount of tokens
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverAddress), // we need to encode the address to bytes
            data: "", // We don't need any data for this example
            tokenAmounts: tokenToSendDetails, // this needs to be of type EVMTokenAmount[] as you could send multiple tokens
            feeToken: linkTokenAddress, // The token used to pay for the fee
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})) // We don't need any extra args for this example
        });
        return message;
    }

    function sendMessage(
        address receiverAddress,
        uint64 destinationChainSelector,
        address tokenToSendAddress,
        uint256 amountToSend,
        address linkTokenAddress,
        address ccipRouterAddress
    ) public {
        vm.startBroadcast();
        // 1. Create the CCIP message
        Client.EVM2AnyMessage memory message =
            createCCIPMessage(receiverAddress, tokenToSendAddress, amountToSend, linkTokenAddress);

        // 2. Approve the router to burn the tokens
        IERC20(tokenToSendAddress).approve(ccipRouterAddress, amountToSend);

        // 4. Approve the router to spend the fees
        uint256 ccipFee = IRouterClient(ccipRouterAddress).getFee(destinationChainSelector, message);
        IERC20(linkTokenAddress).approve(ccipRouterAddress, ccipFee); // Approve the fee
        // 5. Send the message to the router!!
        IRouterClient(ccipRouterAddress).ccipSend(destinationChainSelector, message); // Send the message

        vm.stopBroadcast();
    }
}
