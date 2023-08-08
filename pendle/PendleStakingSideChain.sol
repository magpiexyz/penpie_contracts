// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;
pragma abicoder v2;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { PendleStakingBaseUpg } from "./PendleStakingBaseUpg.sol";

/// @title PendleStakingSideChain
/// @notice PendleStaking Side only get vePendle posistion broadcast from main chain to get boosting yield effect
///         
/// @author Magpie Team

contract PendleStakingSideChain is PendleStakingBaseUpg {
    using SafeERC20 for IERC20;

    constructor() {_disableInitializers();}

    /* ============ Errors ============ */
    error NotSupported();

    function __PendleStakingSideChain_init(
        address _pendle,
        address _WETH,
        address _vePendle,
        address _distributorETH,
        address _pendleRouter,
        address _masterPenpie
    ) public initializer {
        __PendleStakingBaseUpg_init(
            _pendle,
            _WETH,
            _vePendle,
            _distributorETH,
            _pendleRouter,
            _masterPenpie
        );
    }

     /* ============ VePendle Related Functions ============ */

    /// @notice convert PENDLE to mPendle
    /// @param _amount the number of Pendle to convert
    /// @dev the Pendle must already be in the contract
    function convertPendle(
        uint256 _amount,
        uint256[] calldata chainId
    ) public payable override whenNotPaused returns (uint256) {
       revert NotSupported();
    }

    function vote(address[] calldata _pools, uint64[] calldata _weights) external override {
        revert NotSupported();
    }
}
