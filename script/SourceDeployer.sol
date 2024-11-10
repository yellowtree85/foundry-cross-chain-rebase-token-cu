// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RegistryModuleOwnerCustom} from "@ccip/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";

import {RebaseToken} from "../src/RebaseToken.sol";
import {SourcePool} from "../src/SourcePool.sol";
import {Vault} from "../src/Vault.sol";

contract SourceDeployer is Script {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    Register.NetworkDetails networkDetails;

    RebaseToken public token;

    RegistryModuleOwnerCustom registryModuleOwnerCustom;
    TokenAdminRegistry tokenAdminRegistry;

    function setUp() public {
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        networkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        registryModuleOwnerCustom = RegistryModuleOwnerCustom(networkDetails.registryModuleOwnerCustomAddress);
        tokenAdminRegistry = TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress);
    }

    function run() public {
        // NOTE: what can I do instead of this by making it interactive? Do I even need this line if I'm using a wallet for this?
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Step 1) Deploy token
        token = new RebaseToken();

        // Step 2) Deploy SourcePool
        address[] memory allowlist = new address[](0);
        SourcePool sourcePool = new SourcePool(
            RebaseToken(address(token)), allowlist, networkDetails.rmnProxyAddress, networkDetails.routerAddress
        );

        Vault vault = new Vault(token);

        // Step 3) set the vault and pool for the token
        token.setVaultAndPool(address(sourcePool), address(vault));

        // Step 4) Claim Admin role
        registryModuleOwnerCustom.registerAdminViaOwner(address(token));

        // Step 5) Accept Admin role
        tokenAdminRegistry.acceptAdminRole(address(token));

        // Step 6) Link token to pool
        tokenAdminRegistry.setPool(address(token), address(sourcePool));

        vm.stopBroadcast();
    }
}
