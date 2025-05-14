// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PendleVoteManagerBaseUpg} from"./PendleVoteManagerBaseUpg.sol";

import "../interfaces/IPendleStaking.sol";
import "../interfaces/pendle/IPVotingEscrowMainchain.sol";
import "../libraries/math/Math.sol";
import "../interfaces/IVLPenpie.sol";
import "../interfaces/pendle/IPVoteController.sol";

/// @title PendleVoteManagerMainChain (for Ethereum where vePendle lives)
/// @author Magpie Team

contract PendleVoteManagerMainChain is PendleVoteManagerBaseUpg {
    using SafeERC20 for IERC20;

    /* ============ Structs ============ */

    /* ============ State Variables ============ */

    uint64 constant PENDLE_USER_VOTE_MAX_WEIGHT = 1e18;

    IPVoteController public voter; // Pendle voter interface
    IPVotingEscrowMainchain public vePendle; //main contract interact with from pendle side

    mapping(address => bool) remotePendleVoter; // for cross chain, but not in used anymore as we use off chain aggregation now

    /* ============ Events ============ */

    event RemoteDelegateSet(address indexed _user, bool _allowed);
    event ReceiveRemoteCast(bool _isRemotePendleVoter);

    /* ============ Errors ============ */

    /* ============ Constructor ============ */

    constructor() {_disableInitializers();}

    function __PendleVoteManagerMainChain_init(
        IPVoteController _voter,
        IPVotingEscrowMainchain _vePendle,
        IPendleStaking _pendleStaking,
        address _vlPenpie,
        address _endpoint
    ) public initializer {
        __PendleVoteManagerBaseUpg_init(_pendleStaking, _vlPenpie, _endpoint);
        voter = _voter;
        vePendle = _vePendle;
    }

    /* ============ External Getters ============ */

    function totalVotes() public view returns (uint256) {
        return vePendle.balanceOf(address(pendleStaking));
    }

    function vePendlePerLockedPenpie() public view returns (uint256) {
        if (IVLPenpie(vlPenpie).totalLocked() == 0) return 0;
        return totalVotes() * 1e18 / IVLPenpie(vlPenpie).totalLocked();
    }

    function getVoteForMarket(address market) public view returns (uint256) {
        IPVoteController.UserPoolData memory userPoolData = voter
            .getUserPoolVote(address(pendleStaking), market);
        uint256 poolVote = (userPoolData.weight * totalVotes()) / 1e18;
        return poolVote;
    }

    function getVoteForMarkets(
        address[] calldata markets
    ) public view returns (uint256[] memory votes) {
        uint256 length = markets.length;
        votes = new uint256[](length);
        for (uint256 i; i < length; i++) {
            votes[i] = getVoteForMarket(markets[i]);
        }
    }

    function getUserVoteForMarketsInVlPenpie(
        address[] calldata _markets,
        address _user
    ) public view returns (uint256[] memory votes) {
        uint256 length = _markets.length;
        votes = new uint256[](length);
        for (uint256 i; i < length; i++) {
            votes[i] = userVotedForPoolInVlPenpie[_user][_markets[i]];
        }
    }

    /* ============ External Functions ============ */

    function isRemotePendleVoter(address _remotePendleVoter) external view returns(bool) {
        return remotePendleVoter[_remotePendleVoter];
    }

    /// @notice cast all pending votes
    /// @notice we're casting weights to Pendle Finance
    function manualVote(
        address[] calldata _pools,
        uint64[] calldata _weights
    ) external nonReentrant onlyOperator {
        lastCastTime = block.timestamp;
        IPendleStaking(pendleStaking).vote(_pools, _weights);
        emit VoteCasted(msg.sender, lastCastTime);
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

    /* ============ Admin Functions ============ */

    function setRemoteDelegate(
        address _user,
        bool _allowed
    ) external onlyOwner {
        remotePendleVoter[_user] = _allowed;
        emit RemoteDelegateSet(_user, _allowed);
    }
}
