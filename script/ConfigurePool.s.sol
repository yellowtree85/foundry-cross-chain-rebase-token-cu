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
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(address(remotePoolAddress));

        TokenPool.ChainUpdate[] memory chains = new TokenPool.ChainUpdate[](1);
        chains[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddresses,
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
        uint64[] memory remoteChainSelectorsToRemove = new uint64[](0);
        tokenPool.applyChainUpdates(remoteChainSelectorsToRemove, chains);

        vm.stopBroadcast();
    }
}
