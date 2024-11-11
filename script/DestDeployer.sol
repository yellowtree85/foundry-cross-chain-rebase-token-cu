// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

import {DestRebaseToken} from "../src/DestRebaseToken.sol";
import {DestPool} from "../src/DestPool.sol";

contract DestDeployer is Script {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    Register.NetworkDetails networkDetails;

    DestRebaseToken public token;

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
        token = new DestRebaseToken();

        // Step 2) Deploy pool
        address[] memory allowlist = new address[](0);
        DestPool pool = new DestPool(
            IERC20(address(token)), allowlist, networkDetails.rmnProxyAddress, networkDetails.routerAddress
        );

        // Step 3) set pool on the token contract for permissions
        token.setPool(address(pool));

        // Step 4) Claim Admin role
        registryModuleOwnerCustom.registerAdminViaOwner(address(token));

        // Step 5) Accept Admin role
        tokenAdminRegistry.acceptAdminRole(address(token));

        // Step 6) Link token to pool in the token admin registry
        tokenAdminRegistry.setPool(address(token), address(pool));

        vm.stopBroadcast();
    }
}
