// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Vault} from "../src/Vault.sol";

contract Deposit is Script {
    uint256 public SEND_VAULE = 0.1 ether;

    function depositFunds(address vault) public {
        // Deposit to the vault
        Vault(payable(vault)).deposit{value: SEND_VAULE}();
    }

    function run(address vault) external {
        // Deposit to the vault
        depositFunds(vault);
    }
}

contract Redeem is Script {
    function redeemFunds(address vault) public {
        // Redeem from the vault
        Vault(payable(vault)).redeem(type(uint256).max);
    }

    function run(address vault) external {
        redeemFunds(vault);
    }
}
