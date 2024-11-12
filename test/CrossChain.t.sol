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

contract CrossChainTest is Test {
    address public owner = makeAddr("owner");
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    uint256 public SEND_VALUE = 1e5;

    uint256 sepoliaFork;
    uint256 zksyncSepoliaFork;

    DestRebaseToken destRebaseToken;
    SourceRebaseToken sourceRebaseToken;

    DestPool destPool;
    SourcePool sourcePool;

    TokenAdminRegistry tokenAdminRegistrySepolia;
    TokenAdminRegistry tokenAdminRegistryZksyncSepolia;

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
    Register.NetworkDetails zksyncSepoliaNetworkDetails;

    RegistryModuleOwnerCustom registryModuleOwnerCustomSepolia;
    RegistryModuleOwnerCustom registryModuleOwnerCustomZksyncSepolia;

    Vault vault;

    SourceDeployer sourceDeployer;
    BridgeTokens bridgeTokens;

    function setUp() public {
        address[] memory allowlist = new address[](0);

        sourceDeployer = new SourceDeployer();

        // 1. Setup the Sepolia and ZKsync forks
        sepoliaFork = vm.createSelectFork("eth");
        zksyncSepoliaFork = vm.createFork("zksync");

        //NOTE: what does this do?
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // 2. Deploy and configure on the source chain: Sepolia
        //sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        //(sourceRebaseToken, sourcePool, vault) = sourceDeployer.run(owner);

        vm.startPrank(owner);
        sourceRebaseToken = new SourceRebaseToken();
        console.log("source rebase token address");
        console.log(address(sourceRebaseToken));
        // Deploy the token pool on ZKsync
        console.log("Deploying token pool on Sepolia");
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
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

        // 3. Deploy and configure on the destination chain: Zksync
        // Deploy the token contract on ZKsync
        vm.selectFork(zksyncSepoliaFork);
        vm.startPrank(owner);
        destRebaseToken = new DestRebaseToken();
        console.log("dest rebase token address");
        console.log(address(destRebaseToken));
        // Deploy the token pool on ZKsync
        console.log("Deploying token pool on ZKsync");
        zksyncSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        destPool = new DestPool(
            IERC20(address(destRebaseToken)),
            allowlist,
            zksyncSepoliaNetworkDetails.rmnProxyAddress,
            zksyncSepoliaNetworkDetails.routerAddress
        );
        // Set pool on the token contract for permissions
        destRebaseToken.setPool(address(destPool));
        // Claim role on Zksync
        registryModuleOwnerCustomZksyncSepolia =
            RegistryModuleOwnerCustom(zksyncSepoliaNetworkDetails.registryModuleOwnerCustomAddress);
        registryModuleOwnerCustomZksyncSepolia.registerAdminViaOwner(address(destRebaseToken));
        // Accept role on Zksync
        tokenAdminRegistryZksyncSepolia = TokenAdminRegistry(zksyncSepoliaNetworkDetails.tokenAdminRegistryAddress);
        tokenAdminRegistryZksyncSepolia.acceptAdminRole(address(destRebaseToken));
        // Link token to pool in the token admin registry
        tokenAdminRegistryZksyncSepolia.setPool(address(destRebaseToken), address(destPool));
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
        vm.prank(owner);
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

    function setTokenConfig() public {}

    function depositTokens() public {
        vm.selectFork(sepoliaFork);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
    }

    function testBridgeTokens()
        public
        configureTokenPool(
            sepoliaFork,
            sourcePool,
            destPool,
            IRebaseToken(address(destRebaseToken)),
            zksyncSepoliaNetworkDetails
        )
        configureTokenPool(
            zksyncSepoliaFork,
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
        vm.startPrank(alice);
        // Give the user some ETH
        vm.deal(alice, SEND_VALUE);
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
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})), // We don't need any extra args for this example
            feeToken: sepoliaNetworkDetails.linkAddress // The token used to pay for the fee
        });
        // Get and approve the fees
        uint256 ccipFee = IRouterClient(sepoliaNetworkDetails.routerAddress).getFee(
            zksyncSepoliaNetworkDetails.chainSelector, message
        );
        // Give the user the fee amount of LINK
        deal(sepoliaNetworkDetails.linkAddress, alice, ccipFee);
        IERC20(sepoliaNetworkDetails.linkAddress).approve(sepoliaNetworkDetails.routerAddress, ccipFee); // Approve the fee

        IRouterClient(sepoliaNetworkDetails.routerAddress).ccipSend(zksyncSepoliaNetworkDetails.chainSelector, message); // Send the message
        vm.stopPrank();
    }
}
