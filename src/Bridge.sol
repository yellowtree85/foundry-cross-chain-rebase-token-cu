// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title Bridge Tokens
 * @author yellowtree
 * @notice Bridge tokens from one chain to another
 */
contract Bridge is Ownable, AccessControl {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error Bridge__ChainIdNotExist();
    error Bridge__NetworkDetailsNotExist(uint256 chainId);
    error Bridge__NotSupportBridgeToSourceChain();
    error Bridge__DestinationChainIdSelectorNotExist();
    error Bridge__ReceiverAddressNotExist();
    error Bridge__TokenSendAddressNotExist();
    error Bridge__AmountToSendMustGreaterThanZero();

    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 private constant BRIDGE_TOKEN_ROLE = keccak256("BRIDGE_TOKEN_ROLE"); // Role for bridging tokens(vaulue transfer)

    constructor() Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev grants the bridge token role to an address. This is only called by the protocol owner.
     * @param _address the address to grant the role to
     */
    function grantBridgeTokenRole(address _address) external onlyOwner {
        _grantRole(BRIDGE_TOKEN_ROLE, _address);
    }

    /**
     * @dev bridge token from one chain to another
     * @param receiverAddress the address to receive the token on the destination chain
     * @param destinationChainSelector the chain id of the destination chain
     * @param tokenToSendAddress the address of the token to send
     * @param amountToSend the amount of the token to send
     */
    function bridgeToken(
        address receiverAddress,
        uint64 destinationChainSelector,
        address tokenToSendAddress,
        uint256 amountToSend,
        address linkTokenAddress,
        address routerAddress
    ) public onlyRole(BRIDGE_TOKEN_ROLE) returns (bool) {
        console2.log("Bridge token from chain: ", block.chainid, " to chain: ", destinationChainSelector);
        if (receiverAddress == address(0)) {
            revert Bridge__ReceiverAddressNotExist();
        }
        if (destinationChainSelector == 0) {
            revert Bridge__DestinationChainIdSelectorNotExist();
        }

        if (tokenToSendAddress == address(0)) {
            revert Bridge__TokenSendAddressNotExist();
        }
        if (amountToSend == 0) {
            revert Bridge__AmountToSendMustGreaterThanZero();
        }

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: tokenToSendAddress, amount: amountToSend});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverAddress),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: linkTokenAddress,
            // extraArgs: "" // gasLimit: 0 means no gas limit becasue we just send the token it means we would not need gas for this transaction
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})) // gasLimit: 0 means no gas limit becasue we just send the token it means we would not need gas for this transaction
        });
        uint256 ccipFee = IRouterClient(routerAddress).getFee(destinationChainSelector, message);
        IERC20(linkTokenAddress).approve(routerAddress, ccipFee);
        IERC20(tokenToSendAddress).approve(routerAddress, amountToSend);
        IRouterClient(routerAddress).ccipSend(destinationChainSelector, message);
        return true;
    }

    /**
     * @dev get network details for a given chain id
     * @param _chinkId the chain id of the chain to get the network details for
     */
    function getNetworkDetails(uint256 _chinkId) internal returns (Register.NetworkDetails memory) {
        if (_chinkId == 0) {
            revert Bridge__ChainIdNotExist();
        }

        CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork.getNetworkDetails(_chinkId);
        if (
            networkDetails.chainSelector == 0 || networkDetails.routerAddress == address(0)
                || networkDetails.linkAddress == address(0)
        ) {
            revert Bridge__NetworkDetailsNotExist(_chinkId);
        }
        return networkDetails;
    }
}
