// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";

import {SourceRebaseToken} from "../src/SourceRebaseToken.sol";
import {DestRebaseToken} from "../src/DestRebaseToken.sol";

import {SourcePool} from "../src/SourcePool.sol";
import {DestPool} from "../src/DestPool.sol";

import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;

    uint256 arbSepoliaFork;
    uint256 zksyncSepoliaFork;

    DestRebaseToken destRebaseToken;
    SourceRebaseToken sourceRebaseToken;

    DestPool destPool;
    SourcePool sourcePool;

    TokenAdminRegistry tokenAdminRegistryArbSepolia;
    TokenAdminRegistry tokenAdminRegistryZksyncSepolia;

    Register.NetworkDetails arbSepoliaNetworkDetails;
    Register.NetworkDetails zksyncSepoliaNetworkDetails;

    RegistryModuleOwnerCustom registryModuleOwnerCustomArbSepolia;
    RegistryModuleOwnerCustom registryModuleOwnerCustomZksyncSepolia;

    Vault vault;

    function setUp() public {
        address[] memory allowlist = new address[](0);

        // 1. Setup the Arbitrum and ZKsync forks
        arbSepoliaFork = vm.createSelectFork("arb");
        zksyncSepoliaFork = vm.createFork("zksync");

        //NOTE: what does this do?
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // 2. Deploy and configure on the source chain: Arbitrum
        // 2. a) Deploy the token contract on Arbitrum
        sourceRebaseToken = new SourceRebaseToken();
        // 2. b) Deploy the pool contract on Arbitrum
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        sourcePool = new SourcePool(
            IERC20(address(sourceRebaseToken)),
            allowlist,
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        // 2. c) Deploy the vault on Arbitrum
        vault = new Vault(IRebaseToken(address(sourceRebaseToken)));
        // 2. d) configure the token
        sourceRebaseToken.setVaultAndPool(address(sourcePool), address(vault));
        // 2. e) Claim role on Arbitrum
        tokenAdminRegistryArbSepolia = TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress);
        tokenAdminRegistryArbSepolia.acceptAdminRole(address(sourceRebaseToken));
        // 2. f) Accept role on Arbitrum
        registryModuleOwnerCustomArbSepolia =
            RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress);
        registryModuleOwnerCustomArbSepolia.registerAdminViaOwner(address(sourceRebaseToken));
        // 2. g) Link token to pool in the token admin registry
        tokenAdminRegistryArbSepolia.setPool(address(sourceRebaseToken), address(sourcePool));

        // 3. Deploy and configure on the destination chain: Zksync
        // Deploy the token contract on ZKsync
        vm.selectFork(zksyncSepoliaFork);
        destRebaseToken = new DestRebaseToken();
        // Deploy the token pool on ZKsync
        zksyncSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        destPool = new DestPool(
            IERC20(address(destRebaseToken)),
            allowlist,
            zksyncSepoliaNetworkDetails.rmnProxyAddress,
            zksyncSepoliaNetworkDetails.routerAddress
        );
        // Claim role on Zksync
        registryModuleOwnerCustomZksyncSepolia =
            RegistryModuleOwnerCustom(zksyncSepoliaNetworkDetails.registryModuleOwnerCustomAddress);
        registryModuleOwnerCustomZksyncSepolia.registerAdminViaOwner(address(destRebaseToken));
        // Accept role on Zksync
        tokenAdminRegistryZksyncSepolia = TokenAdminRegistry(zksyncSepoliaNetworkDetails.tokenAdminRegistryAddress);
        tokenAdminRegistryZksyncSepolia.acceptAdminRole(address(destRebaseToken));
        // Link token to pool in the token admin registry
        tokenAdminRegistryZksyncSepolia.setPool(address(destRebaseToken), address(destPool));
    }

    function testConfigureTokenPoolArb() public {
        // NOTE: remove?
        vm.selectFork(arbSepoliaFork);
        TokenPool.ChainUpdate[] memory chains = new TokenPool.ChainUpdate[](1);
        chains = new TokenPool.ChainUpdate[](1);
        chains[0] = TokenPool.ChainUpdate({
            remoteChainSelector: arbSepoliaNetworkDetails.chainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(address(destPool)),
            remoteTokenAddress: abi.encode(address(destRebaseToken)),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 100_000, rate: 167}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 100_000, rate: 167})
        });
        sourcePool.applyChainUpdates(chains);
    }

    function testConfigureTokenPoolZksync() public {
        // NOTE: remove?
        vm.selectFork(zksyncSepoliaFork);
        TokenPool.ChainUpdate[] memory chains = new TokenPool.ChainUpdate[](1);
        chains = new TokenPool.ChainUpdate[](1);
        chains[0] = TokenPool.ChainUpdate({
            remoteChainSelector: zksyncSepoliaNetworkDetails.chainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(address(sourcePool)),
            remoteTokenAddress: abi.encode(address(sourceRebaseToken)),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 100_000, rate: 167}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 100_000, rate: 167})
        });
        destPool.applyChainUpdates(chains);
    }
}
