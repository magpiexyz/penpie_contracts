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
/// @notice  PendleVoteManagerSideChain acts like a delegated vote which stores only voting information on that chain, and will have to cast to PendleVoteManageMainChain on Ethereum
///         then later to be casted to Pendle.
///
///         VoteManagerSubChain --(cross chain cast vote)--> VoteManagerMainChain --(cast vote)--> Pendle
///
/// @author Penpie Team
contract PendleVoteManagerSideChain is PendleVoteManagerBaseUpg {
    using SafeERC20 for IERC20;

    /* ============ Structs ============ */

    /* ============ State Variables ============ */

    uint256[1000] private __gap;

    mapping(uint256 => int256) public deltaSinceLastCast; // pid -> delta
    uint256 public mainChainId; // EVM chain Id, NOT layerZero chainId
    uint256 public minRemoteCastGas;

    /* ============ Events ============ */

    event MainChainIdSet(uint256 _oldChainId, uint256 _newChainId);
    event MinRemoteCastGasSet(uint256 _oldCastGas, uint256 _newCastGas);

    /* ============ Errors ============ */
    error RemoteMinGasNotSet();
    error InvalidMinRemoteCastGas();
    error RemoteCastGasNotEnough();

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
        mainChainId = _mainChainId;
    }

    /* ============ External Getters Functions ============ */

    function estimateCastFee(
        bool _payInZRO,
        bytes calldata _adapterParam
    ) public view returns (uint nativeFee, uint zroFee) {
        uint256 length = poolInfos.length;
        UserVote[] memory votes = new UserVote[](length);

        for (uint16 i; i < length; i++) {
            votes[i].pid = i;
            votes[i].weight = deltaSinceLastCast[i];
        }

        if (_getGasLimit(_adapterParam) < minRemoteCastGas)
            revert RemoteCastGasNotEnough();

        return
            estimateVoteFee(
                LayerZeroHelper._getLayerZeroChainId(mainChainId),
                address(this),
                votes,
                _payInZRO,
                _adapterParam
            );
    }

    /* ============ External Functions ============ */

    /// @notice cast all pending votes back to Eth
    /// @notice this function will be gas intensive
    function castVotes() public payable nonReentrant whenNotPaused {
        lastCastTime = block.timestamp;
        uint256 length = poolInfos.length;
        UserVote[] memory votes = new UserVote[](length);

        for (uint16 i; i < length; i++) {
            votes[i].pid = i;
            votes[i].weight = deltaSinceLastCast[i];

            deltaSinceLastCast[i] = 0; // might need a safer way to deal with this
        }

        uint minDstGas = minDstGasLookup[
            LayerZeroHelper._getLayerZeroChainId(mainChainId)
        ][1];
        if (minDstGas == 0 || minRemoteCastGas < minDstGas)
            revert RemoteMinGasNotSet();

        bytes memory lzAdapater = abi.encodePacked(uint16(1), minRemoteCastGas);

        _lzSend(
            LayerZeroHelper._getLayerZeroChainId(mainChainId),
            encodeVote(address(this), votes),
            payable(msg.sender),
            address(0),
            lzAdapater,
            msg.value
        );

        emit VoteCasted(msg.sender, lastCastTime);
    }

    /* ============ Internal Functions ============ */

    function _afterVoteUpdate(
        address _user,
        address _market,
        uint256 _pid,
        int256 _weight
    ) internal override {
        deltaSinceLastCast[_pid] += _weight;
        uint256 epoch = IPenpieBribeManager(bribeManager).exactCurrentEpoch();
        emit Voted(epoch, _user, _market, _pid, _weight);
    }

    /* ============ layerzero Functions ============ */

    function _nonblockingLzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload) internal override { }

    /* ============ Admin Functions ============ */

    function setMainChainId(uint256 _mainChainId) external onlyOwner() {
        uint256 oldChainId = mainChainId;
        mainChainId = _mainChainId;
        emit MainChainIdSet(oldChainId, _mainChainId);
    }

    function setMinRemoteCastGas(uint256 _minRemoteCastGas) external onlyOwner {
        if (
            _minRemoteCastGas <
            minDstGasLookup[LayerZeroHelper._getLayerZeroChainId(mainChainId)][
                1
            ]
        ) revert InvalidMinRemoteCastGas();

        uint256 oldCastGas = minRemoteCastGas;
        minRemoteCastGas = _minRemoteCastGas;
        emit MinRemoteCastGasSet(oldCastGas, _minRemoteCastGas);
    }
}
