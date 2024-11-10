// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {TokenPool} from "@chainlink/contracts-ccip/src/v0.8/ccip/pools/BurnMintTokenPool.sol";
import {RateLimiter} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/RateLimiter.sol";
import {DestPool} from "../src/DestPool.sol";
import {SourcePool} from "../src/SourcePool.sol";

contract ConfigurePoolScript is Script {
    function run(
        address sourceChainPoolAddress,
        uint64 destinationChainSelector,
        address destinationPoolAddress,
        address destinationTokenAddress,
        bool outboundRateLimiterIsEnabled,
        uint128 outboundRateLimiterCapacity,
        uint128 outboundRateLimiterRate,
        bool inboundRateLimiterIsEnabled,
        uint128 inboundRateLimiterCapacity,
        uint128 inboundRateLimiterRate
    ) public {
        // NOTE: what can I do instead of this by making it interactive? Do I even need this line if I'm using a wallet for this?
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        TokenPool tokenPool = TokenPool(tokenPool);

        TokenPool.ChainUpdate[] memory chains = new TokenPool.ChainUpdate[](1);
        chains[0] = TokenPool.ChainUpdate({
            remoteChainSelector: destinationChainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(destinationPoolAddress),
            remoteTokenAddress: abi.encode(destinationTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: outboundRateLimiterIsEnabled,
                capacity: outboundRateLimiterCapacity,
                rate: outboundRateLimiterRate
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: inboundRateLimiterIsEnabled,
                capacity: inboundRateLimiterCapacity,
                rate: inboundRateLimiterRate
            })
        });

        tokenPool.applyChainUpdates(chains);

        vm.stopBroadcast();
    }
}
