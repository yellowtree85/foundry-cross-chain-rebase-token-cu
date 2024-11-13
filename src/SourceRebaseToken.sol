// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {RebaseTokenBase} from "./RebaseTokenBase.sol";

import {IDestRebaseToken} from "./interfaces/IDestRebaseToken.sol";

// NOTE: name, symbol, decimals need to be included
contract SourceRebaseToken is RebaseTokenBase {
    address public s_vault;
    address immutable i_linkToken; // NOTE: change to linkAddress?
    address immutable i_router; // NOTE: change to routerAddress?

    event AccumulatedRateUpdated(uint256 index, uint256 timestamp);
    event VaultAndPoolSet(address vault, address pool);
    event RatesSentCrossChain(uint256 chainSelector, address token, bytes data);
    event InterestRateUpdated(uint256 newInterestRate);

    error RebaseToken__SenderNotPoolOrVault(address sender);
    error NotEnoughBalance(uint256 linkBalance, uint256 fee);

    constructor(address _linkToken, address _router) RebaseTokenBase() {
        i_linkToken = _linkToken;
        i_router = _router;
    }

    modifier onlyPoolOrVault() {
        if (msg.sender != s_pool && msg.sender != s_vault) {
            revert RebaseToken__SenderNotPoolOrVault(msg.sender);
        }
        _;
    }

    function setVaultAndPool(address vault, address pool) external onlyOwner {
        s_vault = vault;
        s_pool = pool;
        emit VaultAndPoolSet(vault, pool);
    }

    // NOTE: is there a way to have this in the base but apply different modifiers
    /// @notice Mints new tokens for a given address.
    /// @param account The address to mint the new tokens to.
    /// @param amount The number of tokens to be minted.
    /// @dev this function increases the total supply.
    function mint(address account, uint256 amount) external onlyPoolOrVault {
        // accumulates the balance of the user
        _beforeUpdate(address(0), account, amount);
        _mint(account, amount);
    }

    /// @notice Burns tokens from the sender.
    /// @param amount The number of tokens to be burned.
    /// @dev this function decreases the total supply.
    function burn(address account, uint256 amount) external onlyPoolOrVault {
        // NOTE: should I have a check for zero?
        // accumulates the balance of the user
        _beforeUpdate(account, address(0), amount);
        _burn(account, amount);
    }

    /**
     * @dev updates the interest rate
     * @param interestRate the new interest rate
     *
     */
    function updateInterestRate(
        uint256 interestRate,
        uint64[] memory destinationChainSelectors,
        address[] memory destinationTokens
    ) external onlyOwner {
        // we need to add the interest accumulated to s_accumulattedRate UP TO when the interest rate changes so that it accouts for all historical interest up to that point.
        _updateAccumulatedInterest();
        s_interestRate = interestRate;
        for (uint256 i = 0; i < destinationChainSelectors.length; i++) {
            bytes memory data = abi.encode(
                abi.encodeWithSelector(IDestRebaseToken.setRates.selector, s_accumulatedInterest, s_interestRate)
            );
            // send a message to the destination chain to update the share to token ratio
            _sendMessagePayLINK(destinationChainSelectors[i], destinationTokens[i], data, 0);
            emit RatesSentCrossChain(destinationChainSelectors[i], destinationTokens[i], data);
        }
        emit InterestRateUpdated(interestRate);
    }

    /**
     * @dev updates the accumulated rate and the last updated timestamp
     * @notice this function should be called every time the interest rate changes.
     * @dev s_accumulatedInterest holds the accumulated interest multiplier UP TO when the interest most recently was updated. It therefore holds all historical interest rates.
     * @dev individual balances etc. will individually calculate any interest that has accumulated since interest rate was last updated since it will be linear witht time.
     *
     */
    function _updateAccumulatedInterest() internal {
        // Calculate the updated accumulated interest
        s_accumulatedInterest = _calculateAccumulatedInterestSinceLastUpdate();
        s_lastUpdatedTimestamp = block.timestamp;
        emit AccumulatedRateUpdated(s_accumulatedInterest, s_lastUpdatedTimestamp);
    }

    function _sendMessagePayLINK(
        uint64 _destinationChainSelector,
        address _receiver,
        bytes memory _data,
        uint256 _amount
    ) internal {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        // address(linkToken) means fees are paid in LINK
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(_receiver, address(i_linkToken), _data, _amount);

        // Get the fee required to send the CCIP message
        uint256 fees = IRouterClient(i_router).getFee(_destinationChainSelector, evm2AnyMessage);

        if (fees > IERC20(i_linkToken).balanceOf(address(this))) {
            revert NotEnoughBalance(IERC20(i_linkToken).balanceOf(address(this)), fees);
        }

        // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
        IERC20(i_linkToken).approve(address(i_router), fees);

        // approve the Router to spend tokens on contract's behalf. It will spend the amount of the given token
        // transferFrom sender
        approve(address(i_router), _amount);

        // Send the message through the router
        IRouterClient(i_router).ccipSend(_destinationChainSelector, evm2AnyMessage);
    }

    /// @notice Construct a CCIP message.
    /// @dev This function will create an EVM2AnyMessage struct with all the necessary information for programmable tokens transfer.
    /// @param _receiver The address of the receiver.
    /// @param _feeToken The token to be used for fees.
    /// @param _data The data to be sent.
    /// @param _amount The amount of the token to be transferred.
    /// @return Client.EVM2AnyMessage Returns an EVM2AnyMessage struct which contains information for sending a CCIP message.
    function _buildCCIPMessage(address _receiver, address _feeToken, bytes memory _data, uint256 _amount)
        private
        view
        returns (Client.EVM2AnyMessage memory)
    {
        // Set the token amounts
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        if (_amount != 0) {
            tokenAmounts[0] = Client.EVMTokenAmount({token: address(this), amount: _amount});
        }
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        return Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver), // ABI-encoded receiver address
            data: _data, // ABI-encoded string
            tokenAmounts: tokenAmounts, // The amount and type of token being transferred
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit
                Client.EVMExtraArgsV2({
                    gasLimit: 200_000, // Gas limit for the callback on the destination chain
                    allowOutOfOrderExecution: true // Allows the message to be executed out of order relative to other messages from the same sender
                })
            ),
            // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
            feeToken: _feeToken // Set to address(0) for native gas
        });
    }
}
