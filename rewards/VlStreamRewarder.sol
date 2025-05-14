// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { StreamRewarder } from "./StreamRewarder.sol";

import { ILocker } from "../interfaces/ILocker.sol";
import { IMasterPenpie } from "../interfaces/IMasterPenpie.sol";

/**
 * @title VlStreamRewarder Contract
 * @notice This contract extends the StreamRewarder to handle reward distribution exclusively to vlLTP in a locked
 * state.
 */
contract VlStreamRewarder is StreamRewarder {
    using SafeERC20 for IERC20;

    /* ================ State Variables ==================== */
    ILocker public vlToken;
    address public underlying;

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }
    /// @notice Initializes the VlStreamRewarder contract.
    /// @param _masterPenpie The address of the MasterListapie contract.
    /// @param _rewardQueuer The address of the reward queuer.
    /// @param _receiptToken The address of the receipt token.
    /// @param _underlying The address of the underlying token.
    /// @param _duration The duration over which rewards are distributed.

    function __VlStreamRewarder_init(
        address _masterPenpie,
        address _rewardQueuer,
        address _receiptToken,
        address _underlying,
        uint256 _duration
    )
        public
        initializer
    {
        super.initialize(_masterPenpie, _rewardQueuer, _receiptToken, _duration);
        __ReentrancyGuard_init();
        vlToken = ILocker(_receiptToken);
        underlying = _underlying;
    }

    /* ============ External Getters ============ */
    /// @notice Fetches the balance of staked tokens for a user from vlListapie contract.
    /// @param _account The address of the user.
    /// @return The amount of staked tokens.

    function balanceOf(address _account) public view override returns (uint256) {
        return vlToken.getUserTotalLocked(_account);
    }

    /// @notice Returns the total staked amount of the vlToken in locked state
    /// @return The total locked amount of the vlToken
    function totalStaked() public view override returns (uint256) {
        return vlToken.totalLocked();
    }
}
