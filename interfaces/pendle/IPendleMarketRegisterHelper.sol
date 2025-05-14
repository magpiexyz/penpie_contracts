// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

interface IPendleMarketRegisterHelper {
    function registerPenpiePool(address _market) external;
    function addPenpieBribePool(address _market) external;
}
