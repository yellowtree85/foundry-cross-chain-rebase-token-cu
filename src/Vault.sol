// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/IRebaseToken.sol";
import "./interfaces/IBridge.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20Permit} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

contract Vault {
    IRebaseToken public immutable i_rebaseToken;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);
    event BridgeToken(address indexed sender, uint256 indexed destChainId, address indexed receiver, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error Vault__RedeemFailed();
    error Vault__BridgeTokenFailed();
    error Vault__ChainIdNotExist();
    error Vault__NetworkDetailsNotExist(uint256 chainId);
    error Vault__NotSupportBridgeToSourceChain();
    error Vault__DestinationChainIdSelectorNotExist();
    error Vault__ReceiverAddressNotExist();
    error Vault__TokenSendAddressNotExist();
    error Vault__AmountToSendMustGreaterThanZero();
    error Vault__LinkTokenAddressNotExist();
    error Vault__RouterAddressNotExist();

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    // allows the contract to receive rewards
    receive() external payable {}

    /**
     * @dev deposits ETH into the valut and mints equivalent rebase tokens to the user
     */
    function deposit() external payable {
        i_rebaseToken.mint(msg.sender, msg.value, i_rebaseToken.getInterestRate());
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @dev redeems rebase token for the underlying asset
     * @param _amount the amount being redeemed
     *
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        i_rebaseToken.burn(msg.sender, _amount);
        // executes redeem of the underlying asset
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    /**
     * @dev bridge token to a different chain
     * @param _receiverAddress  the address to receive the bridged token
     * @param _destinationChainSelector  the chain id of the destination chain
     * @param _tokenToSendAddress  the address of the token to be bridged
     * @param _amountToSend    the amount of the token to be bridged
     * @param _linkTokenAddress the address of the LINK token used for CCIP fees
     * @param _routerAddress the address of the CCIP router
     */
    function bridgeToken(
        address _receiverAddress,
        uint64 _destinationChainSelector,
        address _tokenToSendAddress,
        uint256 _amountToSend,
        address _linkTokenAddress,
        address _routerAddress
    ) external {
        _validateBridgeToken(
            _receiverAddress,
            _destinationChainSelector,
            _tokenToSendAddress,
            _amountToSend,
            _linkTokenAddress,
            _routerAddress
        );

        // RebaseToken is ERC20Permit off line, so we can use permit to approve the token transfer
        // IERC20Permit(_tokenToSendAddress).permit(
        //     msg.sender,
        //     address(this),
        //     _amountToSend,
        //     deadline,
        //     v, r, s
        // );
        IERC20(_tokenToSendAddress).transferFrom(
            msg.sender,
            address(this),
            _amountToSend
        );
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: _tokenToSendAddress, amount: _amountToSend});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiverAddress),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: _linkTokenAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})) // gasLimit: 0 means no gas limit becasue we just send the token it means we would not need gas for this transaction
        });
        uint256 ccipFee = IRouterClient(_routerAddress).getFee(_destinationChainSelector, message);
        IERC20(_linkTokenAddress).approve(_routerAddress, ccipFee);
        IERC20(_tokenToSendAddress).approve(_routerAddress, _amountToSend);
        IRouterClient(_routerAddress).ccipSend(_destinationChainSelector, message);
        emit BridgeToken(msg.sender, _destinationChainSelector, _receiverAddress, _amountToSend);
    }

    /**
     * @dev validates the parameters for bridging token
     * @param _receiverAddress the address to receive the bridged token
     * @param _destinationChainSelector  the chain id of the destination chain
     * @param _tokenToSendAddress  the address of the token to be bridged
     * @param _amountToSend    the amount of the token to be bridged
     */
    function _validateBridgeToken(
        address _receiverAddress,
        uint64 _destinationChainSelector,
        address _tokenToSendAddress,
        uint256 _amountToSend,
        address _linkTokenAddress,
        address _routerAddress
    ) internal pure {
        if (_receiverAddress == address(0)) {
            revert Vault__ReceiverAddressNotExist();
        }
        if (_destinationChainSelector == 0) {
            revert Vault__DestinationChainIdSelectorNotExist();
        }

        if (_tokenToSendAddress == address(0)) {
            revert Vault__TokenSendAddressNotExist();
        }
        if (_amountToSend == 0) {
            revert Vault__AmountToSendMustGreaterThanZero();
        }
        if (_linkTokenAddress == address(0)) {
            revert Vault__LinkTokenAddressNotExist();
        }
        if (_routerAddress == address(0)) {
            revert Vault__RouterAddressNotExist();
        }
    }

    /**
     * @dev returns the address of the rebase token
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
