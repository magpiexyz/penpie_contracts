// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { PendleVoteManagerBaseUpg } from "./PendleVoteManagerBaseUpg.sol";

import "../interfaces/IPendleStaking.sol";
import "../libraries/math/Math.sol";
import "../libraries/layerZero/LayerZeroHelper.sol";
import "../interfaces/pendle/IPVoteController.sol";
import "../interfaces/IPenpieBribeManager.sol";

/// @title PendleVoteManagerMainChain (for Ethereum where vePendle lives)
/// @author Penpie Team
contract PendleVoteManagerSideChain is PendleVoteManagerBaseUpg {
    using SafeERC20 for IERC20;

    /* ============ Structs ============ */

    /* ============ State Variables ============ */
    // This is improper slot reserve given, so no need to modify this gap array.
    uint256[1000] private __gap;

    mapping(uint256 => int256) public deltaSinceLastCast_Deprecated; // for cross chain, but not in used anymore as we use off chain aggregation now
    uint256 public mainChainId_Deprecated; // for cross chain, but not in used anymore as we use off chain aggregation now
    uint256 public minRemoteCastGas_Deprecated; // for cross chain, but not in used anymore as we use off chain aggregation now

    /* ============ Events ============ */

    /* ============ Errors ============ */

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __PendleVoteManagerSideChain_init(
        IPendleStaking _pendleStaking,
        address _vlPenpie,
        address _endpoint,
        uint256 _mainChainId
    ) public initializer {
        __PendleVoteManagerBaseUpg_init(_pendleStaking, _vlPenpie, _endpoint);
        mainChainId_Deprecated = _mainChainId;
    }

    /* ============ layerzero Functions ============ */

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal override {
        revert NotUse();
    }    

}
