// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";

// forge script ./script/InspectCCIPLocalSimulatorFork.s.sol:InspectCCIPLocalSimulatorFork --rpc-url $SEPOLIA_RPC_URL --account updraft --broadcast
contract InspectCCIPLocalSimulatorFork is Script {
    // https://docs.chain.link/ccip/tutorials/cross-chain-tokens/register-from-eoa-burn-mint-foundry
    // https://github.com/Cyfrin/ccip-cct-starter/blob/main/README.md
    function run() public {
        // https://docs.chain.link/chainlink-local/build/ccip/foundry/local-simulator-fork
        // CCIPLocalSimulatorFork::getNetworkDetails(11155111 [1.115e7])
        // {
        //     chainSelector:16015286601757825753,
        //     routerAddress:0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59,
        //     linkAddress:0x779877A7B0D9E8603169DdbD7836e478b4624789,
        //     wrappedNativeAddress:0x097D90c9d3E0B50Ca60e1ae45F6A81010f9FB534,
        //     ccipBnMAddress:0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05,
        //     ccipLnMAddress:0x466D489b6d36E7E3b824ef491C225F5830E81cC1,
        //     rmnProxyAddress:0xba3f6251de62dED61Ff98590cB2fDf6871FbB991,
        //     registryModuleOwnerCustomAddress:0x62e731218d0D47305aba2BE3751E7EE9E5520790,
        //     tokenAdminRegistryAddress:0x95F29FEE11c5C55d26cCcf1DB6772DE953B37B82
        // }
        CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        console2.log("networkDetails.registryModuleOwnerCustomAddress", networkDetails.registryModuleOwnerCustomAddress);
        console2.log("networkDetails.tokenAdminRegistryAddress", networkDetails.tokenAdminRegistryAddress);
        console2.log("networkDetails.rmnProxyAddress", networkDetails.rmnProxyAddress);
        console2.log("networkDetails.routerAddress", networkDetails.routerAddress);
        console2.log("networkDetails.linkTokenAddress", networkDetails.linkAddress);
    }
}
