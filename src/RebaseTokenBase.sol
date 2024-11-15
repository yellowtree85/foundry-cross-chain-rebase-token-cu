// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract RebaseTokenBase is ERC20, Ownable {
    uint256 public constant PRECISION_FACTOR = 1e18; // Used to handle fixed-point calculations
    address public s_pool; // the pool address (needed for access modifiers)

    event ToInterestAccrued(address user, uint256 balance);
    event FromInterestAccrued(address user, uint256 balance);

    constructor() Ownable(msg.sender) ERC20("RebaseToken", "RBT") {}

    /// @dev need to implement on the inheriting contract
    /// @dev this needs to be called in _beforeUpdate() to apply the accrued interest
    function _mintAccruedInterest(address _user) internal virtual returns (uint256 newUserBalance);

    function getPool() external view returns (address) {
        return s_pool;
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

    /// @notice Mints new tokens for a given address.
    /// @param account The address to mint the new tokens to.
    /// @param amount The number of tokens to be minted.
    /// @dev this function increases the total supply.
    function mint(address account, uint256 amount) public virtual {
        // accumulates the balance of the user so it is up to date with any interest accumulated.
        // also sets the user's accumulated rate (source token) or last updated timestamp (destination token)
        _beforeUpdate(address(0), account);
        _mint(account, amount);
    }

    /// @notice Burns tokens from the sender.
    /// @param amount The number of tokens to be burned.
    /// @dev this function decreases the total supply.
    function burn(address account, uint256 amount) public virtual {
        // accumulates the balance of the user so it is up to date with any interest accumulated.
        // also sets the user's accumulated rate (source token) or last updated timestamp (destination token)
        _beforeUpdate(account, address(0));
        _burn(account, amount);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        // accumulates the balance of the user so it is up to date with any interest accumulated.
        // also sets the user's accumulated rate (source token) or last updated timestamp (destination token)
        _beforeUpdate(msg.sender, recipient);
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        // accumulates the balance of the user so it is up to date with any interest accumulated.
        // also sets the user's accumulated rate (source token) or last updated timestamp (destination token)
        _beforeUpdate(sender, recipient);
        return super.transferFrom(sender, recipient, amount);
    }

    /**
     * @dev executes the transfer of tokens, invoked by _transfer(), _mint() and _burn()
     * @param _from the address from which transfer the tokens
     * @param _to the destination address
     *
     */
    function _beforeUpdate(address _from, address _to) internal virtual {
        if (_from != address(0)) {
            // we are burning or transferring tokens
            // mint any accrued interest since the last time the user's balance was updated
            (uint256 fromBalance) = _mintAccruedInterest(_from);
            // if (fromBalance - _value == 0) {
            //     // NOTE: do i need to do this?
            //     s_userInterestRate[_from] = 0;
            //     s_userLastUpdatedTimestamp[_from] = 0;
            // }
            emit FromInterestAccrued(_from, fromBalance);
        }
        if (_to != address(0)) {
            // we are minting or transferring tokens
            // mint any accrued interest since the last time the user's balance was updated
            (uint256 toBalance) = _mintAccruedInterest(_to);
            emit ToInterestAccrued(_to, toBalance);
        }
    }
}
