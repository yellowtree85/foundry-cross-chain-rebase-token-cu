// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/IRebaseToken.sol";

contract Vault {
    IRebaseToken public immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    function deposit() external payable {
        // 1. checks and 2. effects are performed in here
        i_rebaseToken.mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @dev redeems rebase token for the underlying asset
     * @param _amount the amount being redeemed
     *
     */
    function redeem(uint256 _amount) external {
        // 1. Checks and effects are performed in herre
        i_rebaseToken.burn(msg.sender, _amount);

        // executes redeem of the underlying asset
        // NOTE: Implement on the vault contract
        // updateAccumulatedRate(); // NOTE: surely this only needs to be called if interestRate changes? otherwise it's just linear with time anyway?
        payable(msg.sender).transfer(_amount);
        //vault.redeem(msg.sender, amountToRedeem);
        emit Redeem(msg.sender, _amount);
    }
}
