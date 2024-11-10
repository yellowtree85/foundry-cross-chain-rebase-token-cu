// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

contract VaultTest is Test {
    modifier depositToVault() {
        // Deposit to the vault
        _;
    }

    function testDeposit() public {
        // Deposit to the vault
        // Send tokens cross-chain
        // check the balances of both chains
    }

    function testRedeem() public depositToVault {}
}
