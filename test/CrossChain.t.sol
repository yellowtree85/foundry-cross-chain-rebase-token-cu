// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {console, Test} from "forge-std/Test.sol";

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

import {SourceDeployer} from "../script/Deployer.s.sol";
import {BridgeTokens} from "../script/BridgeTokens.s.sol";

// Tests to include
// Test you can bridge tokens - check the balance is correct
// test you can bridge a portion of tokens - check balances are correct
// test you can bridge and then bridge back all balance - check balances
// test you can bridge and then bridge back a portion - check balances
contract CrossChainTest is Test {
    address public owner = makeAddr("owner");
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    uint256 public SEND_VALUE = 1e5;

    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    DestRebaseToken destRebaseToken;
    SourceRebaseToken sourceRebaseToken;

    DestPool destPool;
    SourcePool sourcePool;

    TokenAdminRegistry tokenAdminRegistrySepolia;
    TokenAdminRegistry tokenAdminRegistryarbSepolia;

    // struct NetworkDetails {
    //     uint64 chainSelector;
    //     address routerAddress;
    //     address linkAddress;
    //     address wrappedNativeAddress;
    //     address ccipBnMAddress;
    //     address ccipLnMAddress;
    //     address rmnProxyAddress;
    //     address registryModuleOwnerCustomAddress;
    //     address tokenAdminRegistryAddress;
    // }
    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    RegistryModuleOwnerCustom registryModuleOwnerCustomSepolia;
    RegistryModuleOwnerCustom registryModuleOwnerCustomarbSepolia;

    Vault vault;

    SourceDeployer sourceDeployer;
    BridgeTokens bridgeTokens;

    function setUp() public {
        address[] memory allowlist = new address[](0);

        sourceDeployer = new SourceDeployer();

        // 1. Setup the Sepolia and arb forks
        sepoliaFork = vm.createSelectFork("eth");
        arbSepoliaFork = vm.createFork("arb");

        //NOTE: what does this do?
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // 2. Deploy and configure on the source chain: Sepolia
        //sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        //(sourceRebaseToken, sourcePool, vault) = sourceDeployer.run(owner);

        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        sourceRebaseToken =
            new SourceRebaseToken(sepoliaNetworkDetails.linkAddress, sepoliaNetworkDetails.routerAddress);
        console.log("source rebase token address");
        console.log(address(sourceRebaseToken));
        console.log("Deploying token pool on Sepolia");
        sourcePool = new SourcePool(
            IERC20(address(sourceRebaseToken)),
            allowlist,
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );
        // deploy the vault
        vault = new Vault(IRebaseToken(address(sourceRebaseToken)));
        // Set pool on the token contract for permissions
        sourceRebaseToken.setVaultAndPool(address(vault), address(sourcePool));
        // Claim role
        registryModuleOwnerCustomSepolia =
            RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress);
        registryModuleOwnerCustomSepolia.registerAdminViaOwner(address(sourceRebaseToken));
        // Accept role
        tokenAdminRegistrySepolia = TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress);
        tokenAdminRegistrySepolia.acceptAdminRole(address(sourceRebaseToken));
        // Link token to pool in the token admin registry
        tokenAdminRegistrySepolia.setPool(address(sourceRebaseToken), address(sourcePool));
        vm.stopPrank();

        // 3. Deploy and configure on the destination chain: arb
        // Deploy the token contract on arb
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);
        console.log("Deploying token on arb");
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        destRebaseToken = new DestRebaseToken(arbSepoliaNetworkDetails.routerAddress);
        console.log("dest rebase token address");
        console.log(address(destRebaseToken));
        // Deploy the token pool on arb
        console.log("Deploying token pool on arb");
        destPool = new DestPool(
            IERC20(address(destRebaseToken)),
            allowlist,
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        // Set pool on the token contract for permissions
        destRebaseToken.setPool(address(destPool));
        // Claim role on arb
        registryModuleOwnerCustomarbSepolia =
            RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress);
        registryModuleOwnerCustomarbSepolia.registerAdminViaOwner(address(destRebaseToken));
        // Accept role on arb
        tokenAdminRegistryarbSepolia = TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress);
        tokenAdminRegistryarbSepolia.acceptAdminRole(address(destRebaseToken));
        // Link token to pool in the token admin registry
        tokenAdminRegistryarbSepolia.setPool(address(destRebaseToken), address(destPool));
        vm.stopPrank();
    }

    modifier configureTokenPool(
        uint256 fork,
        TokenPool localPool,
        TokenPool remotePool,
        IRebaseToken remoteToken,
        Register.NetworkDetails memory networkDetails
    ) {
        vm.selectFork(fork);
        vm.startPrank(owner);
        TokenPool.ChainUpdate[] memory chains = new TokenPool.ChainUpdate[](1);
        chains = new TokenPool.ChainUpdate[](1);
        chains[0] = TokenPool.ChainUpdate({
            remoteChainSelector: networkDetails.chainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(address(remotePool)),
            remoteTokenAddress: abi.encode(address(remoteToken)),
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: true,
                capacity: 20000000000000000000,
                rate: 100000000000000000
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: true,
                capacity: 20000000000000000000,
                rate: 100000000000000000
            })
        });
        localPool.applyChainUpdates(chains);
        vm.stopPrank();
        _;
    }

    function testBridgeTokens()
        public
        configureTokenPool(
            sepoliaFork,
            sourcePool,
            destPool,
            IRebaseToken(address(destRebaseToken)),
            arbSepoliaNetworkDetails
        )
        configureTokenPool(
            arbSepoliaFork,
            destPool,
            sourcePool,
            IRebaseToken(address(sourceRebaseToken)),
            sepoliaNetworkDetails
        )
    {
        // NOTE: can I use the script instead?
        address alice = makeAddr("alice");
        // We are working on the source chain (Sepolia)
        vm.selectFork(sepoliaFork);
        // Pretend a user is interacting with the protocol
        // Give the user some ETH
        vm.deal(alice, SEND_VALUE);
        vm.startPrank(alice);
        // Deposit to the vault and receive tokens
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        // bridge the tokens
        console.log(IERC20(address(sourceRebaseToken)).balanceOf(alice));
        // Create the message to send
        Client.EVMTokenAmount[] memory tokenToSendDetails = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({
            token: address(sourceRebaseToken),
            amount: IERC20(address(sourceRebaseToken)).balanceOf(alice)
        });
        tokenToSendDetails[0] = tokenAmount;
        // Approve the router to burn tokens on users behalf
        IERC20(address(sourceRebaseToken)).approve(sepoliaNetworkDetails.routerAddress, SEND_VALUE);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(alice), // we need to encode the address to bytes
            data: "", // We don't need any data for this example
            tokenAmounts: tokenToSendDetails, // this needs to be of type EVMTokenAmount[] as you could send multiple tokens
            extraArgs: "", // We don't need any extra args for this example
            feeToken: sepoliaNetworkDetails.linkAddress // The token used to pay for the fee
        });
        // Get and approve the fees
        uint256 ccipFee =
            IRouterClient(sepoliaNetworkDetails.routerAddress).getFee(arbSepoliaNetworkDetails.chainSelector, message);
        vm.stopPrank();
        // Give the user the fee amount of LINK
        ccipLocalSimulatorFork.requestLinkFromFaucet(alice, ccipFee);
        vm.startPrank(alice);
        IERC20(sepoliaNetworkDetails.linkAddress).approve(sepoliaNetworkDetails.routerAddress, ccipFee); // Approve the fee
        console.log("source user accumulated rate: %d", sourceRebaseToken.getUserAccumulatedRate(alice));
        console.log("source user balance: %d", IERC20(address(sourceRebaseToken)).balanceOf(alice));
        IRouterClient(sepoliaNetworkDetails.routerAddress).ccipSend(arbSepoliaNetworkDetails.chainSelector, message); // Send the message
        vm.stopPrank();

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);
        console.log("destination user accumulated rate: %d", destRebaseToken.getUserAccumulatedRate(alice));
        uint256 destBalance = IERC20(address(destRebaseToken)).balanceOf(alice);
        console.log("Destination balance: %d", destBalance);
    }

    function testChangeInterestRate()
        public
        configureTokenPool(
            sepoliaFork,
            sourcePool,
            destPool,
            IRebaseToken(address(destRebaseToken)),
            arbSepoliaNetworkDetails
        )
        configureTokenPool(
            arbSepoliaFork,
            destPool,
            sourcePool,
            IRebaseToken(address(sourceRebaseToken)),
            sepoliaNetworkDetails
        )
    {
        // Advance the time by 100 seconds on sepolia
        vm.selectFork(sepoliaFork);
        vm.warp(block.timestamp + 100);
        vm.roll(block.timestamp + 100);

        // Advance the time by 100 seconds on arb
        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 100);
        vm.roll(block.timestamp + 100);

        vm.selectFork(sepoliaFork);
        // Update the interest rate on the source token. This will send a cross-chain message to the supplied destination tokens.
        uint64[] memory chainSelectors = new uint64[](1);
        chainSelectors[0] = arbSepoliaNetworkDetails.chainSelector;
        address[] memory destTokens = new address[](1);
        destTokens[0] = address(destRebaseToken);
        deal(sepoliaNetworkDetails.linkAddress, address(sourceRebaseToken), 100e18);
        vm.prank(owner);
        sourceRebaseToken.setInterestRate(5e13, chainSelectors, destTokens);
        uint256 sourceInterestRate = sourceRebaseToken.s_interestRate();
        uint256 sourceAccumulatedInterest = sourceRebaseToken.s_accumulatedInterest();
        console.log("Source time: %d", block.timestamp);
        console.log("Source last updated timestamp: %d", sourceRebaseToken.s_lastUpdatedTimestamp());
        console.log("Source interest rate: %d", sourceInterestRate);
        console.log("Source accumulated interest: %d", sourceAccumulatedInterest);

        //vm.selectFork(arbSepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);
        uint256 destInterestRate = destRebaseToken.s_interestRate();
        uint256 destAccumulatedInterest = destRebaseToken.s_accumulatedInterest();
        console.log("Destination time: %d", block.timestamp);
        console.log("Destination last updated timestamp: %d", destRebaseToken.s_lastUpdatedTimestamp());
        console.log("Destination interest rate: %d", destInterestRate);
        console.log("Destination accumulated interest: %d", destAccumulatedInterest);

        assertEq(sourceInterestRate, destInterestRate);
        assertEq(sourceAccumulatedInterest, destAccumulatedInterest);
    }
}
