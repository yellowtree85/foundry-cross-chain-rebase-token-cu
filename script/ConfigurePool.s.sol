// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/BurnMintTokenPool.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";

contract ConfigurePoolScript is Script {
    function createChainUpdateObject(
        uint64 remoteChainSelector,
        address remotePoolAddress,
        address remoteTokenAddress,
        bool outboundRateLimiterIsEnabled,
        uint128 outboundRateLimiterCapacity,
        uint128 outboundRateLimiterRate,
        bool inboundRateLimiterIsEnabled,
        uint128 inboundRateLimiterCapacity,
        uint128 inboundRateLimiterRate
    ) public pure returns (TokenPool.ChainUpdate[] memory) {
        TokenPool.ChainUpdate[] memory chains = new TokenPool.ChainUpdate[](1);
        chains[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(remotePoolAddress),
            remoteTokenAddress: abi.encode(remoteTokenAddress),
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
        return chains;
    }

    function run(
        address ccipChainPoolAddress,
        uint64 remoteChainSelector,
        address remotePoolAddress,
        address remoteTokenAddress,
        bool outboundRateLimiterIsEnabled,
        uint128 outboundRateLimiterCapacity,
        uint128 outboundRateLimiterRate,
        bool inboundRateLimiterIsEnabled,
        uint128 inboundRateLimiterCapacity,
        uint128 inboundRateLimiterRate
    ) public {
        vm.startBroadcast();

        TokenPool tokenPool = TokenPool(ccipChainPoolAddress);
        TokenPool.ChainUpdate[] memory chains = createChainUpdateObject(
            remoteChainSelector,
            remotePoolAddress,
            remoteTokenAddress,
            outboundRateLimiterIsEnabled,
            outboundRateLimiterCapacity,
            outboundRateLimiterRate,
            inboundRateLimiterIsEnabled,
            inboundRateLimiterCapacity,
            inboundRateLimiterRate
        );
        tokenPool.applyChainUpdates(chains);

        vm.stopBroadcast();
    }
}
