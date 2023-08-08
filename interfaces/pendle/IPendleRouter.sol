// SPDX-License-Identifier:MIT
pragma solidity =0.8.19;

import "../../libraries/MarketApproxLib.sol";
import "../../libraries/ActionBaseMintRedeem.sol";

interface IPendleRouter {
    function redeemDueInterestAndRewards(
        address user,
        address[] calldata sys,
        address[] calldata yts,
        address[] calldata markets
    ) external;
}
