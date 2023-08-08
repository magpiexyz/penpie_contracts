// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

interface IPendleMarketMeta {
    function readTokens() external view returns (
        address _SY,
        address _PT,
        address _YT
    );
}