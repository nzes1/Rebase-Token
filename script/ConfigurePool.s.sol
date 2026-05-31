// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {RateLimiter} from "@chainlink/contracts-ccip/contracts/libraries/RateLimiter.sol";
import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";
import {Script} from "forge-std/Script.sol";

contract ConfigurePoolScript is Script {

    function run(
        address _localPool,
        uint64 _remoteChainSelector,
        address _remotePool,
        address _remoteToken,
        bool _outboundRateLimiterIsEnabled,
        uint128 _outboundRateLimiterCapacity,
        uint128 _outboundRateLimiterRate,
        bool _inboundRateLimiterIsEnabled,
        uint128 _inboundRateLimiterCapacity,
        uint128 _inboundRateLimiterRate
    )
        public
    {
        vm.startBroadcast();
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        bytes[] memory _remotePoolAddresses = new bytes[](1);
        _remotePoolAddresses[0] = abi.encodePacked(_remotePool);
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: _remoteChainSelector,
            remotePoolAddresses: _remotePoolAddresses,
            remoteTokenAddress: abi.encode(_remoteToken),
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: _outboundRateLimiterIsEnabled,
                capacity: _outboundRateLimiterCapacity,
                rate: _outboundRateLimiterRate
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: _inboundRateLimiterIsEnabled,
                capacity: _inboundRateLimiterCapacity,
                rate: _inboundRateLimiterRate
            })
        });

        // Configure the chains updates via the pool
        TokenPool(_localPool).applyChainUpdates(new uint64[](0), chainsToAdd);

        vm.stopBroadcast();
    }

}
