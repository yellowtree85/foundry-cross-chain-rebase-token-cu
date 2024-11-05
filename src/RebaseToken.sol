// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// NOTE: name, symbol, decimals need to be included
contract RebaseToken is ERC20, Ownable {
    uint256 public constant UINT_MAX_VALUE = type(uint256).max; //NOTE: how can I not use this? where is it used?
    uint256 constant PRECISION_FACTOR = 10 ** 27; // Used to handle fixed-point calculations
    uint256 public s_interestRate = 5 * PRECISION_FACTOR / 1000;
    uint256 public s_accumulatedRate = PRECISION_FACTOR; // Initial rate of 1 (no growth)
    uint256 public s_lastUpdatedTimestamp;
    address public s_pool;
    address public s_vault;

    mapping(address => uint256) private userIndexes; // NOTE: spelling

    event CumulativeIndexUpdated(uint256 index, uint256 timestamp);
    event MintOnDeposit(address indexed user, uint256 amount, uint256 balanceIncrease, uint256 index);
    //event BurnOnWithdraw(address indexed user, uint256 amount, uint256 balanceIncrease, uint256 index);
    event Redeem(address indexed user, uint256 amount, uint256 balanceIncrease, uint256 index);
    event BalanceTransfer(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 fromBalanceIncrease,
        uint256 toBalanceIncrease,
        uint256 fromIndex,
        uint256 toIndex
    );
    event Burn(address indexed user, uint256 amount, uint256 balanceIncrease, uint256 index);

    error RebaseToken__CannotRedeemZero();
    error RebaseToken__AmountGreaterThanBalance(uint256 amount, uint256 balance);
    error RebaseToken__SenderNotVault(address sender);
    error RebaseToken__SenderNotPool(address sender);
    error RebaseToken__CannotTransferZero();
    error RebaseToken__SenderNotPoolOrVault(address sender);

    constructor(address _pool, address _vault) Ownable(msg.sender) ERC20("RebaseToken", "RBT") {
        s_lastUpdatedTimestamp = block.timestamp;
        s_pool = _pool;
        s_vault = _vault;
    }

    modifier onlyVault() {
        if (msg.sender != s_vault) {
            revert RebaseToken__SenderNotVault(msg.sender);
        }
        _;
    }

    modifier onlyPoolOrVault() {
        if (msg.sender != s_pool && msg.sender != s_vault) {
            revert RebaseToken__SenderNotPoolOrVault(msg.sender);
        }
        _;
    }§

    modifier onlyPool() {
        if (msg.sender != s_pool) {
            revert RebaseToken__SenderNotPool(msg.sender);
        }
        _;
    }

    function getUserInfo(address user) external returns (uint256, uint256, uint256) {
        return (userIndexes[user], s_accumulatedRate, s_lastUpdatedTimestamp);
    }

    function setUserInfo(address user, uint256 index, uint256 rate, uint256 timestamp) external onlyPool {
        userIndexes[user] = index;
        s_accumulatedRate = rate;
        s_lastUpdatedTimestamp = timestamp;
    }

    /// @notice Mints new tokens for a given address.
    /// @param account The address to mint the new tokens to.
    /// @param amount The number of tokens to be minted.
    /// @dev this function increases the total supply.
    function mint(address account, uint256 amount) external onlyPoolOrVault {
        if (amount == 0) {
            revert RebaseToken__CannotTransferZero();
        }

        // accumulates the balance of the user
        (,, uint256 balanceIncrease, uint256 index) = _accumulateBalanceInternal(account);

        // mint an equivalent amount of tokens to cover the new deposit
        _mint(account, amount);

        emit MintOnDeposit(account, amount, balanceIncrease, index);
    }

    /// @notice Burns tokens from the sender.
    /// @param amount The number of tokens to be burned.
    /// @dev this function decreases the total supply.
    function burn(address account, uint256 amount) external onlyPool {
        if (amount == 0) {
            revert RebaseToken__CannotTransferZero();
        }

        // accumulates the balance of the user
        (, uint256 currentBalance, uint256 balanceIncrease, uint256 index) = _accumulateBalanceInternal(account);

        //if amount is equal to uint(-1), the user wants to redeem everything
        if (amount == UINT_MAX_VALUE) {
            amount = currentBalance;
        }

        if (amount > currentBalance) {
            revert RebaseToken__AmountGreaterThanBalance(amount, currentBalance);
        }

        // burns tokens equivalent to the amount requested
        _burn(account, amount);

        //reset the user data if the remaining balance is 0
        if (currentBalance - amount == 0) {
            userIndexes[account] = 0;
        }

        emit Burn(account, amount, balanceIncrease, userIndexes[account]);
    }

    /**
     * @dev redeems rebase token for the underlying asset
     * @param _amount the amount being redeemed
     *
     */
    function redeem(uint256 _amount) external {
        if (_amount <= 0) {
            revert RebaseToken__CannotRedeemZero();
        }

        // accumulates the balance of the user
        (, uint256 currentBalance, uint256 balanceIncrease, uint256 index) = _accumulateBalanceInternal(msg.sender);

        uint256 amountToRedeem = _amount;

        //if amount is equal to uint(-1), the user wants to redeem everything
        if (_amount == UINT_MAX_VALUE) {
            amountToRedeem = currentBalance;
        }

        if (amountToRedeem > currentBalance) {
            revert RebaseToken__AmountGreaterThanBalance(amountToRedeem, currentBalance);
        }

        // burns tokens equivalent to the amount requested
        _burn(msg.sender, amountToRedeem);

        bool userIndexReset = false; // NOTE: remove as above
        //reset the user data if the remaining balance is 0
        if (currentBalance - amountToRedeem == 0) {
            userIndexes[msg.sender] = 0;
            userIndexReset = true;
        }

        // executes redeem of the underlying asset
        // NOTE: Implement on the vault contract
        // updateAccumulatedRate(); // NOTE: surely this only needs to be called if interestRate changes? otherwise it's just linear with time anyway?
        payable(msg.sender).transfer(amountToRedeem);
        //vault.redeem(msg.sender, amountToRedeem);
        emit Redeem(msg.sender, amountToRedeem, balanceIncrease, userIndexReset ? 0 : index);
    }

    /**
     * @dev calculates the balance of the user, which is the
     * principal balance + interest generated by the principal balance
     * @param _user the user for which the balance is being calculated
     * @return the total balance of the user
     *
     */
    function balanceOf(address _user) public view override returns (uint256) {
        //current principal balance of the user
        uint256 currentPrincipalBalance = super.balanceOf(_user);
        if (currentPrincipalBalance == 0) {
            return 0;
        }
        // shares * current accumulated interest / interest when they deposited
        return currentPrincipalBalance * _getNormalizedIncome() / userIndexes[_user];
    }

    /**
     * @dev returns the principal balance of the user. The principal balance is the last
     * updated stored balance, which does not consider the perpetually accruing interest.
     * @param _user the address of the user
     * @return the principal balance of the user
     *
     */
    function principalBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @dev calculates the total supply of the specific aToken
     * since the balance of every single user increases over time, the total supply
     * does that too.
     * @return the current total supply
     *
     */
    function totalSupply() public view override returns (uint256) {
        uint256 currentSupplyPrincipal = super.totalSupply();

        if (currentSupplyPrincipal == 0) {
            return 0;
        }

        return currentSupplyPrincipal * _getNormalizedIncome();
    }

    /**
     * @dev returns the last index of the user, used to calculate the balance of the user
     * @param _user address of the user
     * @return the last user index
     *
     */
    function getUserIndex(address _user) external view returns (uint256) {
        return userIndexes[_user];
    }

    /**
     * @dev accumulates the accrued interest of the user to the principal balance
     * @param _user the address of the user for which the interest is being accumulated
     * @return the previous principal balance, the new principal balance, the balance increase
     * and the new user index
     *
     */
    function _accumulateBalanceInternal(address _user) internal returns (uint256, uint256, uint256, uint256) {
        //NOTE: DO they lose this is updateAccumlatedRate is called
        //NOTE: make internal function / make it public
        uint256 previousPrincipalBalance = super.balanceOf(_user);

        // Calculate the accrued interest since the last accumulation
        // `balanceOf` uses the accumulated rate to get the updated balance
        uint256 currentBalance = balanceOf(_user);
        uint256 balanceIncrease = currentBalance - previousPrincipalBalance;

        // Mint an amount of tokens equivalent to the interest accrued
        _mint(_user, balanceIncrease);

        // Update the user's index to reflect the new state
        userIndexes[_user] = _getNormalizedIncome(); // NOTE: check this (is it an index or an amount)
        return (previousPrincipalBalance, currentBalance, balanceIncrease, userIndexes[_user]);
    }

    /**
     * @dev returns the normalized income of the rebase token
     * @return the normalized income
     *
     */
    function _getNormalizedIncome() internal view returns (uint256) {
        // Calculate the updated accumulated rate
        return s_accumulatedRate * _calculateLinearInterest() / PRECISION_FACTOR;
    }

    /**
     * @dev calculates the linear interest factor
     * @return the linear interest factor
     *
     */
    function _calculateLinearInterest() internal view returns (uint256) {
        uint256 timeDifference = block.timestamp - s_lastUpdatedTimestamp;
        // Calculate the linear interest factor over the elapsed time
        return (s_interestRate * timeDifference + PRECISION_FACTOR);
    }

    /**
     * @dev updates the accumulated rate and the last updated timestamp
     * @notice this function should be called every time the interest rate changes
     *
     */
    function _updateAccumulatedRate() internal {
        // Calculate the updated cumulative index
        s_accumulatedRate = _getNormalizedIncome();
        s_lastUpdatedTimestamp = block.timestamp;
        // NOTE: send a cross-chain message!
        emit CumulativeIndexUpdated(s_accumulatedRate, s_lastUpdatedTimestamp);
    }

    /**
     * @dev updates the interest rate
     * @param _interestRate the new interest rate
     *
     */
    function updateInterestRate(uint256 _interestRate) external onlyOwner {
        _updateAccumulatedRate();
        s_interestRate = _interestRate;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _interalTransfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        // NOTE: check allowances here
        _interalTransfer(sender, recipient, amount);
        return true;
    }

    /**
     * @dev executes the transfer of aTokens, invoked by both _transfer() and
     *      transferOnLiquidation()
     * @param _from the address from which transfer the aTokens
     * @param _to the destination address
     * @param _value the amount to transfer
     *
     */
    function _interalTransfer(address _from, address _to, uint256 _value) internal {
        if (_value <= 0) {
            revert RebaseToken__CannotTransferZero();
        }

        //cumulate the balance of the sender
        (, uint256 fromBalance, uint256 fromBalanceIncrease, uint256 fromIndex) = _accumulateBalanceInternal(_from);

        //cumulate the balance of the receiver
        (,, uint256 toBalanceIncrease, uint256 toIndex) = _accumulateBalanceInternal(_to);

        //performs the transfer
        super._transfer(_from, _to, _value);

        // NOTE: update as above
        bool fromIndexReset = false;
        //reset the user data if the remaining balance is 0
        if (fromBalance - _value == 0) {
            userIndexes[_from] = 0;
            fromIndexReset = true;
        }

        emit BalanceTransfer(
            _from, _to, _value, fromBalanceIncrease, toBalanceIncrease, fromIndexReset ? 0 : fromIndex, toIndex
        );
    }
}
