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
        sourceRebaseToken = new SourceRebaseToken();
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
        // add rewards to the vault
        vm.deal(address(vault), 1e18);
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
        console.log("Deploying token on Arbitrum");
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        destRebaseToken = new DestRebaseToken();
        console.log("dest rebase token address");
        console.log(address(destRebaseToken));
        // Deploy the token pool on arb
        console.log("Deploying token pool on Arbitrum");
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

    function bridgeTokens(address user, uint256 amountToBridge) public {
        // Create the message to send tokens cross-chain
        vm.startPrank(user);
        Client.EVMTokenAmount[] memory tokenToSendDetails = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount =
            Client.EVMTokenAmount({token: address(sourceRebaseToken), amount: amountToBridge});
        tokenToSendDetails[0] = tokenAmount;
        // Approve the router to burn tokens on users behalf
        IERC20(address(sourceRebaseToken)).approve(sepoliaNetworkDetails.routerAddress, amountToBridge);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user), // we need to encode the address to bytes
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
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, ccipFee);
        vm.startPrank(user);
        IERC20(sepoliaNetworkDetails.linkAddress).approve(sepoliaNetworkDetails.routerAddress, ccipFee); // Approve the fee
        // log the values before bridging
        uint256 sourceBalanceBeforeBridge = IERC20(address(sourceRebaseToken)).balanceOf(user);
        console.log("source balance before bridge: %d", sourceBalanceBeforeBridge);
        uint256 sourceInterestRate = sourceRebaseToken.getInterestRate();
        console.log("source interest rate: %d", sourceInterestRate);

        IRouterClient(sepoliaNetworkDetails.routerAddress).ccipSend(arbSepoliaNetworkDetails.chainSelector, message); // Send the message
        uint256 sourceBalanceAfterBridge = IERC20(address(sourceRebaseToken)).balanceOf(user);
        console.log("Source balance after bridge: %d", sourceBalanceAfterBridge);
        assertEq(sourceBalanceAfterBridge, sourceBalanceBeforeBridge - amountToBridge);
        vm.stopPrank();

        vm.selectFork(arbSepoliaFork);
        // Pretend it takes 15 minutes to bridge the tokens
        vm.warp(block.timestamp + 900);
        vm.roll(block.timestamp + 900);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        console.log("destination user interest rate: %d", destRebaseToken.getUserInterestRate(user));
        uint256 destBalance = IERC20(address(destRebaseToken)).balanceOf(user);
        console.log("Destination balance: %d", destBalance);
        assertEq(destBalance, amountToBridge);
        // check the users interest rate on the destination chain is the interest rate on the source chain at the time of bridging
        assertEq(destRebaseToken.getUserInterestRate(user), sourceInterestRate);
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
        uint256 startBalance = IERC20(address(sourceRebaseToken)).balanceOf(alice);
        assertEq(startBalance, SEND_VALUE);
        vm.stopPrank();
        bridgeTokens(alice, SEND_VALUE);
    }
}
