// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

contract RebaseTokenTest is Test {
    uint256 arbSepoliaFork;
    uint256 zksyncSepoliaFork;

    function setUp() public {
        // Deploy the token contract on both chains
        arbSepoliaFork = vm.createSelectFork(ARB_SEPOLIA_RPC_URL);
        zksyncSepoliaFork = vm.createSelectFork(ZKSYNC_SEPOLIA_RPC_URL);
        // Deploy the token pool on both chains
        // setup the CCIP stuff
        // Deploy the vault on thesource chain
    }

    function testUpdateInterestRate() public {}
}
