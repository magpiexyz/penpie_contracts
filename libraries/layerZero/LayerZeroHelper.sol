// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19; 

library LayerZeroHelper {
    uint256 constant EVM_ADDRESS_SIZE = 20;

    function _getLayerZeroChainId(uint256 chainId) internal pure returns (uint16) {
        if (chainId == 43113) return 10106;
        // fuji testnet
        else if (chainId == 80001) return 10109;
        // mumbai testnet
        else if (chainId == 43114) return 106;
        // avax mainnet
        else if (chainId == 42161) return 110;
        // arbitrum one
        else if (chainId == 1) return 101;
        assert(false);
    }

    function _getOriginalChainId(uint16 chainId) internal pure returns (uint256) {
        if (chainId == 10106) return 43113;
        // fuji testnet
        else if (chainId == 10109) return 80001;
        // mumbai testnet
        else if (chainId == 106) return 43114;
        // avax mainnet
        else if (chainId == 110) return 42161;
        // arbitrum one
        else if (chainId == 101) return 1;
        assert(false);
    }
}