// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";

contract BridgeTokens is Script {
    function run(
        address receiverAddress,
        uint64 destinationChainSelector,
        address tokenToSendAddress,
        uint256 amountToSend,
        address linkTokenAddress,
        address ccipRouterAddress
    ) public {
        // NOTE: what can I do instead of this by making it interactive? Do I even need this line if I'm using a wallet for this?
        //uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast();

        Client.EVMTokenAmount[] memory tokenToSendDetails = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount =
            Client.EVMTokenAmount({token: tokenToSendAddress, amount: amountToSend});
        tokenToSendDetails[0] = tokenAmount;

        IERC20(tokenToSendAddress).approve(ccipRouterAddress, amountToSend);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverAddress), // we need to encode the address to bytes
            data: "", // We don't need any data for this example
            tokenAmounts: tokenToSendDetails, // this needs to be of type EVMTokenAmount[] as you could send multiple tokens
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})), // We don't need any extra args for this example
            feeToken: linkTokenAddress // The token used to pay for the fee
        });

        uint256 ccipFee = IRouterClient(ccipRouterAddress).getFee(destinationChainSelector, message);
        IERC20(linkTokenAddress).approve(ccipRouterAddress, ccipFee); // Approve the fee

        IRouterClient(ccipRouterAddress).ccipSend(destinationChainSelector, message); // Send the message

        vm.stopBroadcast();
    }
}
