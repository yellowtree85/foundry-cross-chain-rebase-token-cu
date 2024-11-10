// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

contract CrossChainTest is Test {
    modifier depositToVault() {
        // Deposit to the vault
        _;
    }

    function setUp() public {
        // Deploy the token contract on both chains
        // Deploy the token pool on both chains
        // setup the CCIP stuff
        // Deploy the vault on thesource chain
    }

    function testSendAllTokensCrossChain() public depositToVault {
        // Deposit to the vault
        // Send tokens cross-chain
        // check the balances of both chains
    }

    function testSendPortionOfTokensCrossChain() public depositToVault {
        // Deposit to the vault
        // Send a portion of the tokens cross-chain
    }
}
