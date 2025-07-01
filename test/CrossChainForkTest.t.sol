// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console, Test} from "forge-std/Test.sol";

import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IOwner} from "@ccip/contracts/src/v0.8/ccip/interfaces/IOwner.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";

import {RebaseToken} from "../src/RebaseToken.sol";

import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";

import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

// Fork tests
// Tests to include
// Test you can bridge tokens - check the balance is correct
// test you can bridge a portion of tokens - check balances are correct
// test you can bridge and then bridge back all balance - check balances
// test you can bridge and then bridge back a portion - check balances
contract CrossChainForkTest is Test {
    address public owner = makeAddr("owner");
    address alice = makeAddr("alice");
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    uint256 public SEND_VALUE = 1e5;

    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    RebaseToken destRebaseToken;
    RebaseToken sourceRebaseToken;

    RebaseTokenPool destPool;
    RebaseTokenPool sourcePool;

    TokenAdminRegistry tokenAdminRegistrySepolia;
    TokenAdminRegistry tokenAdminRegistryarbSepolia;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    RegistryModuleOwnerCustom registryModuleOwnerCustomSepolia;
    RegistryModuleOwnerCustom registryModuleOwnerCustomarbSepolia;

    Vault vault;
    // SourceDeployer sourceDeployer;
    // https://docs.chain.link/chainlink-local/build/ccip/foundry/local-simulator-fork
    // https://docs.chain.link/ccip/tutorials/cross-chain-tokens/register-from-eoa-burn-mint-foundry
    // https://github.com/Cyfrin/ccip-cct-starter/blob/main/README.md

    function setUp() public {
        // To transfer tokens using CCIP in a forked environment, we need the following:

        // Destination chain selector
        // Source CCIP router
        // LINK token for paying CCIP fees
        // A test token contract (such as CCIP-BnM) on both source and destination chains
        // A sender account (Alice)
        // A receiver account (Bob)
        address[] memory allowlist = new address[](0);

        // sourceDeployer = new SourceDeployer();

        // 1. Setup the Sepolia and arb forks which are set up to simulate the Sepolia and arb chains
        sepoliaFork = vm.createSelectFork("eth-sepolia"); // eth in foundry.toml rpc_endpoints section
        arbSepoliaFork = vm.createFork("arb-sepolia");

        // NOTE: Initialize the fork CCIP local simulator:
        // vm.makePersistent is used to make the ccipLocalSimulatorFork address persistent across forks:
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        ////////////////////
        ///////sepolia//////
        ////////////////////
        // 2. Deploy and configure on the source chain: Sepolia
        //sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        //(sourceRebaseToken, sourcePool, vault) = sourceDeployer.run(owner);
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        // Deploy the RebaseToken on Sepolia
        vm.startPrank(owner);
        console.log(
            "______________________________________Deploying token on Sepolia: ______________________________________"
        );
        sourceRebaseToken = new RebaseToken();
        console.log("source rebase token address:"); // 0x3AC83Aae1685E30Bc32fd7dd22Af190ef4630ac8
        console.log(address(sourceRebaseToken));
        // Deploy the token pool on Sepolia
        console.log("Deploying token pool address:"); // 0x8d56dee9098Cf3A525D4999D1acDAF7620D42F6d
        sourcePool = new RebaseTokenPool(
            IERC20(address(sourceRebaseToken)),
            allowlist,
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );
        console.log(address(sourcePool));

        // deploy the vault
        vault = new Vault(IRebaseToken(address(sourceRebaseToken))); // 0x5Aa3260FdFA1eB19737a0092B7C40467721DC620
        // add rewards to the vault
        vm.deal(address(vault), 1e18);
        // Set pool on the token contract for permissions on Sepolia
        // token transfer direction  sender--> router --> token pool --> ccip
        sourceRebaseToken.grantMintAndBurnRole(address(sourcePool));
        sourceRebaseToken.grantMintAndBurnRole(address(vault));

        //   struct TokenAdminRegistry.TokenConfig {
        //     address administrator; // the current administrator of the token
        //     address pendingAdministrator; // the address that is pending to become the new administrator
        //     address tokenPool; // the token pool for this token. Can be address(0) if not deployed or not configured.
        //   }
        //   mapping(address token => TokenConfig) internal s_tokenConfig;
        // Claim Role on Sepolia (set the token pendingAdministrator role to token owner,only owner can claim)
        // set the pendingAdministrator(sourceRebaseToken.owner()) for token on TokenAdminRegistry.TokenConfig
        registryModuleOwnerCustomSepolia =
            RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress);
        registryModuleOwnerCustomSepolia.registerAdminViaOwner(address(sourceRebaseToken));

        tokenAdminRegistrySepolia = TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress);
        TokenAdminRegistry.TokenConfig memory sourceTokenConfig =
            tokenAdminRegistrySepolia.getTokenConfig(address(sourceRebaseToken));
        assertEq(sourceTokenConfig.pendingAdministrator, IOwner(address(sourceRebaseToken)).owner());

        // Accept Role on Sepolia (set the token admin role to token owner,only pendingAdministrator aka msg.sender can accept)
        // set the administrator(sourceRebaseToken.owner()) for token on TokenAdminRegistry.TokenConfig
        tokenAdminRegistrySepolia.acceptAdminRole(address(sourceRebaseToken)); // set the admin for token
        sourceTokenConfig = tokenAdminRegistrySepolia.getTokenConfig(address(sourceRebaseToken));
        assertEq(sourceTokenConfig.pendingAdministrator, address(0));
        assertEq(sourceTokenConfig.administrator, IOwner(address(sourceRebaseToken)).owner());

        // Link token to pool in the token admin registry on Sepolia(only administrator can set)
        // set the tokenPool (RebaseTokenPool) for token on TokenAdminRegistry.TokenConfig
        tokenAdminRegistrySepolia.setPool(address(sourceRebaseToken), address(sourcePool)); // set the tookPool for token
        sourceTokenConfig = tokenAdminRegistrySepolia.getTokenConfig(address(sourceRebaseToken));
        assertEq(sourceTokenConfig.tokenPool, address(sourcePool));
        vm.stopPrank();

        //////////////////////
        ///////arbitrum///////
        //////////////////////
        // 3. Deploy and configure on the destination chain: Arbitrum
        // Deploy the token contract on Arbitrum
        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startPrank(owner);

        console.log(
            "______________________________________Deploying token on Arbitrum______________________________________"
        );
        destRebaseToken = new RebaseToken();
        console.log("dest rebase token address:");
        console.log(address(destRebaseToken)); // 0x88F59F8826af5e695B13cA934d6c7999875A9EeA

        // Deploy the token pool on Arbitrum
        console.log("Deploying token pool address:"); //0xCeF98e10D1e80378A9A74Ce074132B66CDD5e88d
        destPool = new RebaseTokenPool(
            IERC20(address(destRebaseToken)),
            allowlist,
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        console.log(address(destPool));

        // token transfer direction  sender--> router --> token pool --> ccip
        // Set pool on the token contract for permissions on Arbitrum
        destRebaseToken.grantMintAndBurnRole(address(destPool));

        // Claim role on Arbitrum
        registryModuleOwnerCustomarbSepolia =
            RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress);
        registryModuleOwnerCustomarbSepolia.registerAdminViaOwner(address(destRebaseToken));

        // Accept role on Arbitrum
        tokenAdminRegistryarbSepolia = TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress);
        TokenAdminRegistry.TokenConfig memory destTokenConfig =
            tokenAdminRegistryarbSepolia.getTokenConfig(address(destRebaseToken));
        assertEq(destTokenConfig.pendingAdministrator, IOwner(address(destRebaseToken)).owner());

        tokenAdminRegistryarbSepolia.acceptAdminRole(address(destRebaseToken));
        destTokenConfig = tokenAdminRegistryarbSepolia.getTokenConfig(address(destRebaseToken));
        assertEq(destTokenConfig.pendingAdministrator, address(0));
        assertEq(destTokenConfig.administrator, IOwner(address(destRebaseToken)).owner());

        // Link token to pool in the token admin registry on Arbitrum
        tokenAdminRegistryarbSepolia.setPool(address(destRebaseToken), address(destPool));
        destTokenConfig = tokenAdminRegistryarbSepolia.getTokenConfig(address(destRebaseToken));
        assertEq(destTokenConfig.tokenPool, address(destPool));
        vm.stopPrank();
    }

    /**
     * call applyChainUpdates and set the remotePool for token on s_remoteChainConfigs[remoteChainSelector]
     * struct RemoteChainConfig {
     *  RateLimiter.TokenBucket outboundRateLimiterConfig; // Outbound rate limited config, meaning the rate limits for all of the onRamps for the given chain
     *  RateLimiter.TokenBucket inboundRateLimiterConfig; // Inbound rate limited config, meaning the rate limits for all of the offRamps for the given chain
     *  bytes remoteTokenAddress; // Address of the remote token, ABI encoded in the case of a remote EVM chain.
     *  EnumerableSet.Bytes32Set remotePools; // Set of remote pool hashes, ABI encoded in the case of a remote EVM chain.
     * }
     * @notice This function configures the token pools in order to send and receive tokens cross-chain from the source chain to the destination chain
     * @param fork The fork to configure the token pool on local chain
     * @param localPool The token pool on the local chain
     * @param remotePool The token pool on the remote chain
     * @param remoteToken The token on the remote chain
     * @param remoteNetworkDetails The network details of the remote chain
     */
    function configureTokenPool(
        uint256 fork,
        TokenPool localPool,
        TokenPool remotePool,
        IRebaseToken remoteToken,
        Register.NetworkDetails memory remoteNetworkDetails
    ) public {
        vm.selectFork(fork);
        vm.startPrank(owner);

        TokenPool.ChainUpdate[] memory chains = new TokenPool.ChainUpdate[](1);
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(address(remotePool));
        chains[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteNetworkDetails.chainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(address(remoteToken)),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        uint64[] memory remoteChainSelectorsToRemove = new uint64[](0);
        // only owner can call this function
        localPool.applyChainUpdates(remoteChainSelectorsToRemove, chains);

        // check the remote ChainSelector is set correctly
        assertEq(localPool.isSupportedChain(remoteNetworkDetails.chainSelector), true);
        uint64[] memory chainSelectors = localPool.getSupportedChains();
        assertEq(chainSelectors[0], remoteNetworkDetails.chainSelector);

        // CHECK: Check the remote pool address is set correctly
        bytes[] memory remotePoolAddressesFromLocalPool = localPool.getRemotePools(remoteNetworkDetails.chainSelector);
        assertEq(keccak256(remotePoolAddressesFromLocalPool[0]), keccak256(abi.encode(address(remotePool))));
        assertEq(localPool.isRemotePool(remoteNetworkDetails.chainSelector, abi.encode(address(remotePool))), true);

        // check the remote token address is set correctly
        bytes memory remoteTokenAddressFromLocalPool = localPool.getRemoteToken(remoteNetworkDetails.chainSelector);
        // console.log("remoteTokenAddressFromLocalPool1");
        // console.logBytes(remoteTokenAddressFromLocalPool);
        assertEq(keccak256(remoteTokenAddressFromLocalPool), keccak256(abi.encode(address(remoteToken))));
        // console.log("remoteTokenAddressFromLocalPool2");
        // console.logBytes(abi.encode(address(remoteToken)));

        vm.stopPrank();
    }

    /**
     * @notice This function bridges tokens from the source chain to the destination chain and the user who's name is alice will receive the tokens
     * @param amountToBridge The amount of tokens to bridge
     * @param localFork The fork of the source chain
     * @param remoteFork The fork of the destination chain
     * @param localNetworkDetails The network details of the source chain
     * @param remoteNetworkDetails The network details of the destination chain
     * @param localToken The token to bridge
     * @param remoteToken The token to receive
     */
    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        // Create the message to send tokens cross-chain
        vm.selectFork(localFork);

        vm.startPrank(alice);
        // Approve the router to burn tokens on users behalf
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);

        // create the message to send tokens cross-chain
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(alice), // we need to encode the address to bytes
            data: "", // We don't need any data for this example so we don't need to set the gas limit in extraArgs
            tokenAmounts: new Client.EVMTokenAmount[](1), // this needs to be of type EVMTokenAmount[] as you could send multiple tokens
            feeToken: localNetworkDetails.linkAddress, // The token used to pay for the fee
            extraArgs: "" // We don't need any extra args for this example extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 200000})),  extraArgs: Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: 200000, allowOutOfOrderExecution: false})),
        });
        // Set the token and amount to transfer
        message.tokenAmounts[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});
        vm.stopPrank();

        // Get and approve the fees to be able to send the message cross-chain
        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);

        // Give the user the fee amount of LINK from the faucet
        console.log("Requesting %d LINK from faucet for user %s", fee, vm.toString(alice));
        ccipLocalSimulatorFork.requestLinkFromFaucet(alice, fee); // can't use vm.startPrank because it will revert

        vm.startPrank(alice);
        // Approve the router to spend the link token for the fee
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee); // Approve the fee

        // log the balance before bridging
        uint256 balanceBeforeBridge = IERC20(address(localToken)).balanceOf(alice);
        console.log("Local balance before bridge: %d", balanceBeforeBridge); // 100000
        // Send the message cross-chain and call RebaseTokenPool::lockOrBurn
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);
        // Check the balance after bridging on the source chain
        uint256 sourceBalanceAfterBridge = IERC20(address(localToken)).balanceOf(alice);
        console.log("Local balance after bridge: %d", sourceBalanceAfterBridge); // 0
        assertEq(sourceBalanceAfterBridge, balanceBeforeBridge - amountToBridge);
        vm.stopPrank();

        // switch to the destination chain
        vm.selectFork(remoteFork);
        // Pretend it takes 15 minutes to bridge the tokens
        vm.warp(block.timestamp + 900);

        // get initial balance on Arbitrum chain
        uint256 initialArbBalance = IERC20(address(remoteToken)).balanceOf(alice);
        console.log("Remote balance before switchChainAndRouteMessage: %d", initialArbBalance); // 0
        // Switch the chain to the destination chain and route the cross-chain message and execute RebaseTokenPool::releaseOrMint
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);
        // get the user interest rate on the destination chain
        console.log(
            "Remote user interest rate after switchChainAndRouteMessage : %d",
            remoteToken.getUserInterestRate(alice) // 100000
        );

        // check after bridging the balance is correct on the destination chain
        uint256 destBalance = IERC20(address(remoteToken)).balanceOf(alice);
        console.log("Remote balance after switchChainAndRouteMessage: %d", destBalance); // 100000
        assertEq(destBalance, initialArbBalance + amountToBridge);
    }

    /**
     * @notice This function tests the ability to bridge all tokens from the source chain to the destination chain
     */
    function testBridgeAllTokensFirst() public {
        configureTokenPool(
            sepoliaFork, sourcePool, destPool, IRebaseToken(address(destRebaseToken)), arbSepoliaNetworkDetails
        );
        configureTokenPool(
            arbSepoliaFork, destPool, sourcePool, IRebaseToken(address(sourceRebaseToken)), sepoliaNetworkDetails
        );
        // We are working on the source chain (Sepolia)
        vm.selectFork(sepoliaFork);
        // Pretend a user is interacting with the protocol
        // Give the user some ETH
        vm.deal(alice, 10 ether);
        vm.startPrank(alice);
        // Deposit to the vault and receive tokens
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        // bridge the tokens
        console.log("Bridging %d tokens", SEND_VALUE);
        uint256 startBalance = IERC20(address(sourceRebaseToken)).balanceOf(alice);
        assertEq(startBalance, SEND_VALUE);
        vm.stopPrank();

        // bridge all rebase tokens from ethereumSepolia chain to arbitrumSepolia chain
        // bridgeTokens(
        //     SEND_VALUE,
        //     sepoliaFork,
        //     arbSepoliaFork,
        //     sepoliaNetworkDetails,
        //     arbSepoliaNetworkDetails,
        //     sourceRebaseToken,
        //     destRebaseToken
        // );

        ccipLocalSimulatorFork.requestLinkFromFaucet(address(vault), 1 ether); // can't use vm.startPrank because it will revert
        assertEq(IERC20(sepoliaNetworkDetails.linkAddress).balanceOf(address(vault)), 1 ether);
        
        // RebaseToken is ERC20Permit off line, so we can use permit to approve the token transfer
        // IERC20Permit(_tokenToSendAddress).permit(
        //     msg.sender,
        //     address(this),
        //     _amountToSend,
        //     deadline,
        //     v, r, s
        // );
        vm.startPrank(alice);
        IERC20(address(sourceRebaseToken)).approve(address(vault), SEND_VALUE);
        vault.bridgeToken(
            alice,
            arbSepoliaNetworkDetails.chainSelector,
            address(sourceRebaseToken),
            SEND_VALUE,
            sepoliaNetworkDetails.linkAddress,
            sepoliaNetworkDetails.routerAddress
        );
        vm.stopPrank();
    }

    /**
     * @notice This function tests the ability to bridge a portion of tokens from the source chain to the destination chain
     */
    function testBridgeAllTokensBack() public {
        configureTokenPool(
            sepoliaFork, sourcePool, destPool, IRebaseToken(address(destRebaseToken)), arbSepoliaNetworkDetails
        );
        configureTokenPool(
            arbSepoliaFork, destPool, sourcePool, IRebaseToken(address(sourceRebaseToken)), sepoliaNetworkDetails
        );
        // We are working on the source chain (Sepolia)
        vm.selectFork(sepoliaFork);
        // Pretend a user is interacting with the protocol
        // Give the user some ETH
        vm.deal(alice, SEND_VALUE);
        vm.startPrank(alice);
        // Deposit to the vault and receive tokens
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        // bridge the tokens
        console.log("Bridging %d tokens", SEND_VALUE);
        uint256 startBalance = IERC20(address(sourceRebaseToken)).balanceOf(alice);
        assertEq(startBalance, SEND_VALUE);
        vm.stopPrank();
        // bridge all rebase tokens from ethereumSepolia chain to arbitrumSepolia chain
        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sourceRebaseToken,
            destRebaseToken
        );

        // bridge back ALL TOKENS to the source chain after 1 hour
        vm.selectFork(arbSepoliaFork);
        console.log("User Balance Before Warp: %d", destRebaseToken.balanceOf(alice));
        vm.warp(block.timestamp + 3600);
        console.log("User Balance After Warp: %d", destRebaseToken.balanceOf(alice));
        uint256 destBalance = IERC20(address(destRebaseToken)).balanceOf(alice);
        console.log("Amount bridging back %d tokens ", destBalance);
        bridgeTokens(
            destBalance,
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            destRebaseToken,
            sourceRebaseToken
        );
    }

    function testBridgeTwiceAndGetBack() public {
        configureTokenPool(
            sepoliaFork, sourcePool, destPool, IRebaseToken(address(destRebaseToken)), arbSepoliaNetworkDetails
        );
        configureTokenPool(
            arbSepoliaFork, destPool, sourcePool, IRebaseToken(address(sourceRebaseToken)), sepoliaNetworkDetails
        );
        // We are working on the source chain (Sepolia)
        vm.selectFork(sepoliaFork);
        // Pretend a user is interacting with the protocol
        // Give the user some ETH
        vm.deal(alice, SEND_VALUE);
        vm.startPrank(alice);
        // Deposit to the vault and receive tokens
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();

        uint256 startBalance = IERC20(address(sourceRebaseToken)).balanceOf(alice);
        assertEq(startBalance, SEND_VALUE);
        vm.stopPrank();

        // bridge half tokens to the destination chain
        // bridge the tokens
        console.log("Bridging %d tokens (first bridging event)", SEND_VALUE / 2);
        bridgeTokens(
            SEND_VALUE / 2,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sourceRebaseToken,
            destRebaseToken
        );

        // wait 1 hour for the interest to accrue
        vm.selectFork(sepoliaFork);
        vm.warp(block.timestamp + 3600);
        uint256 newSourceBalance = IERC20(address(sourceRebaseToken)).balanceOf(alice);
        // bridge the tokens
        console.log("Bridging %d tokens (second bridging event)", newSourceBalance);
        bridgeTokens(
            newSourceBalance,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sourceRebaseToken,
            destRebaseToken
        );

        // bridge back ALL TOKENS to the source chain after 1 hour
        vm.selectFork(arbSepoliaFork);
        // wait an hour for the tokens to accrue interest on the destination chain
        console.log("User Balance Before Warp: %d", destRebaseToken.balanceOf(alice));
        vm.warp(block.timestamp + 3600);
        console.log("User Balance After Warp: %d", destRebaseToken.balanceOf(alice));
        uint256 destBalance = IERC20(address(destRebaseToken)).balanceOf(alice);
        console.log("Amount bridging back %d tokens ", destBalance);
        bridgeTokens(
            destBalance,
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            destRebaseToken,
            sourceRebaseToken
        );
    }
}
