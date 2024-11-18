// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

import {RebaseToken} from "../src/RebaseToken.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";

contract TokenDeployer is Script {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    Register.NetworkDetails networkDetails;

    RegistryModuleOwnerCustom registryModuleOwnerCustom;
    TokenAdminRegistry tokenAdminRegistry;

    bytes32 public constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    function run() public returns (RebaseToken token, RebaseTokenPool pool) {
        // NOTE: what can I do instead of this by making it interactive? Do I even need this line if I'm using a wallet for this?
        //uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // NOTE: in the test I have already done this though? Is this a problem
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        networkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        registryModuleOwnerCustom = RegistryModuleOwnerCustom(networkDetails.registryModuleOwnerCustomAddress);
        tokenAdminRegistry = TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress);
        vm.startBroadcast();

        // Step 1) Deploy token
        token = new RebaseToken();

        // Step 2) Deploy pool
        address[] memory allowlist = new address[](0);
        pool = new RebaseTokenPool(
            IERC20(address(token)), allowlist, networkDetails.rmnProxyAddress, networkDetails.routerAddress
        );

        token.grantMintAndBurnRole(address(pool));

        // Step 4) Claim Admin role
        registryModuleOwnerCustom.registerAdminViaOwner(address(token));

        // Step 5) Accept Admin role
        tokenAdminRegistry.acceptAdminRole(address(token));

        // Step 6) Link token to pool
        tokenAdminRegistry.setPool(address(token), address(pool));

        vm.stopBroadcast();
    }
}

// Only on the source chain!
contract VaultDeployer is Script {
    bytes32 public constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    function run(address _rebaseToken) public returns (Vault vault) {
        // NOTE: what can I do instead of this by making it interactive? Do I even need this line if I'm using a wallet for this?
        //uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast();

        // Step 1) Deploy the vault
        vault = new Vault(IRebaseToken(_rebaseToken));

        // Step 2) Claim burn and mint role
        IRebaseToken(_rebaseToken).grantMintAndBurnRole(address(vault));

        vm.stopBroadcast();
    }
}
