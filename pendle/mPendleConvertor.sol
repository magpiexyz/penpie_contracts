// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { mPendleConvertorBaseUpg } from "./mPendleConvertorBaseUpg.sol";
import "../interfaces/IPendleStaking.sol";

/// @title mPendleConvertor simply mints 1 mPendle for each mPendle convert.
/// @author Magpie Team
/// @notice mPENDLE is a token minted when 1 PENDLE deposit on penpie, the deposit is irreversible, user will get mPendle instead.

contract mPendleConvertor is Initializable, mPendleConvertorBaseUpg {
    using SafeERC20 for IERC20;

    /* ============ Constructor ============ */
    constructor() {_disableInitializers();}

    function __mPendleConvertor_init(
        address _pendleStaking,
        address _pendle,
        address _mPendleOFT,
        address _masterPenpie
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        pendleStaking = _pendleStaking;
        pendle = _pendle;
        mPendleOFT = _mPendleOFT;
        masterPenpie = _masterPenpie;
    }

    /* ============ Admin Functions ============ */

    // only for mainChain
    function lockAllPendle(
        uint256[] calldata chainId
    ) external payable onlyOwner {
        if(pendleStaking == address(0)) revert PendleStakingNotSet();
        uint256 allPendle = IERC20(pendle).balanceOf(address(this));

        IERC20(pendle).safeApprove(pendleStaking, allPendle);

        uint256 mintedVePendleAmount = IPendleStaking(pendleStaking)
            .convertPendle{ value: msg.value }(allPendle, chainId);

        emit PendleConverted(allPendle, mintedVePendleAmount);
    }
}
