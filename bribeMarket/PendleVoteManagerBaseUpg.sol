// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { NonblockingLzAppUpgradeable } from"@layerzerolabs/solidity-examples/contracts/contracts-upgradable/lzApp/NonblockingLzAppUpgradeable.sol";
import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PendleVoteManagerBaseUpg } from "./PendleVoteManagerBaseUpg.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "../interfaces/IPendleStaking.sol";
import "../libraries/math/Math.sol";
import "../interfaces/IVLPenpie.sol";
import "../interfaces/IPenpieBribeManager.sol";

/// @title PendleVoteManager Base contract, which include common functions for pendle voter on Ethereum and side chains
/// @notice Pendle Vote manager is designed for vlPNP holder to vote for Pendle emission for Pendle Markets
///         
///         Bribe is designed as only lives on 1 chain, determined by which chain the corresponding liqudity is host on Pendle, for example, bribe for 
///         GLP will be on Arbitrum while bribe for anrkETH, stETH will be on Ethereum.
///
/// @author Penpie Team
abstract contract PendleVoteManagerBaseUpg is NonblockingLzAppUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;
    
    /* ============ Structs ============ */

    struct Pool {       
        address market;  // the pendle market
        uint256 totalVoteInVlPenpie;
        uint256 chainId; // layer zero chainId (https://layerzero.gitbook.io/docs/technical-reference/mainnet/supported-chain-ids) where bribe lives
        bool isActive;
    }

    struct UserVote {
        int256 weight;
        uint16 pid;
    }

    struct LzParams {
        address payable refundAddress;
        address zroPaymentAddress;
        bytes adapterParams;
    }

    /* ============ State Variables ============ */

    IPendleStaking public pendleStaking; //TODO: currently only used for harvesting vePendle from Pendle
    address public vlPenpie; // vlPenpie address
    address public bribeManager;

    Pool[] public poolInfos;   // IMPORTANT!!! Pool setup has to be exact the same order acrros all chains, this is an important assumption!!!
    mapping(address => uint256) public marketToPid;

    mapping(address => uint256) public userTotalVotedInVlPenpie; // unit = locked Penpie
    mapping(address => mapping(address => uint256)) public userVotedForPoolInVlPenpie; // unit = locked Penpie, key: [_user][_market]

    uint256 public totalVlPenpieInVote;
    uint256 public lastCastTime;

    /* ===== 1st upgrade ===== */
    mapping(address => bool) public allowedOperator;

    uint256[49] private __gap;

    /* ============ Events ============ */

    event AddPool(address indexed market, uint256 _pid);
    event DeactivatePool(address indexed market, uint256 _pid);
    event VoteCasted(address indexed caster, uint256 timestamp);
    event Voted(uint256 indexed _epoch, address indexed _user, address _market, uint256 indexed _pid, int256 _weight);
    event UpdateOperatorStatus(address indexed _user, bool _status);
    event BribeManagerSet(address indexed _bribeManager);
    event UpdatePool(uint256 _pid, uint256 _chainId, address indexed _market, bool _isActive);
    event MarketPIDForceSet(address indexed _market, uint256 _pid);

    /* ============ Errors ============ */

    error PoolNotActive();
    error NotEnoughVote();
    error OutOfPoolIndex();
    error ZeroAddressError();
    error OnlyBribeManager();
    error OnlyOperator();
    error NotUse();
    error InvalidPool();    

    /* ============ Constructor ============ */

    function __PendleVoteManagerBaseUpg_init(IPendleStaking _pendleStaking, address _vlPenpie, address _endpoint) internal onlyInitializing {
        __NonblockingLzAppUpgradeable_init(_endpoint);
        __ReentrancyGuard_init();
        __Pausable_init();
        pendleStaking = _pendleStaking;
        vlPenpie = _vlPenpie;
    }

    /* ============ Modifiers ============ */
    
    modifier onlyBribeManager() {
        if (msg.sender != bribeManager) revert OnlyBribeManager();
        _;
    }

    modifier onlyOperator() {
        if (!allowedOperator[msg.sender]) revert OnlyOperator();
        _;
    }

    /* ============ External Getters ============ */

    function isPoolActive(uint256 _pid) external view returns (bool) {
        return poolInfos[_pid].isActive;
    }

    function getUserVotable(address _user) public view returns (uint256) {
        return IVLPenpie(vlPenpie).getUserTotalLocked(_user);
    }

    function getUserVoteForPoolsInVlPenpie(
        address[] calldata markets,
        address _user
    ) public view returns (uint256[] memory votes) {
        uint256 length = markets.length;
        votes = new uint256[](length);
        for (uint256 i; i < length; i++) {
            votes[i] = userVotedForPoolInVlPenpie[_user][markets[i]];
        }
    }

    function getPoolsLength() external view returns (uint256) {
        return poolInfos.length;
    }

    function getVlPenpieVoteForPools(
        uint256[] calldata _pids
    ) public view returns (uint256[] memory vlPenpieVotes) {
        uint256 length = _pids.length;
        vlPenpieVotes = new uint256[](length);
        for (uint256 i; i < length; i++) {
            Pool storage pool = poolInfos[_pids[i]];
            vlPenpieVotes[i] = pool.totalVoteInVlPenpie;
        }
    }

    /* ============ External Functions ============ */

    function vote(UserVote[] memory _votes) external virtual nonReentrant whenNotPaused {
        _updateVoteAndCheck(msg.sender, _votes);
        if (userTotalVotedInVlPenpie[msg.sender] > getUserVotable(msg.sender)) revert NotEnoughVote();
    }

    /* ============ Internal Functions ============ */

    function _updateVoteAndCheck(address _user, UserVote[] memory _userVotes) internal {
        uint256 length = _userVotes.length;
        int256 totalUserVote;

        for (uint256 i; i < length; i++) {
            if (_userVotes[i].pid >= poolInfos.length) revert PoolNotActive();
            Pool storage pool = poolInfos[_userVotes[i].pid];

            int256 weight = _userVotes[i].weight;
            totalUserVote += weight;

            if (weight != 0) {
                if (weight > 0) {
                    uint256 absVal = uint256(weight);
                    pool.totalVoteInVlPenpie += absVal;
                    userVotedForPoolInVlPenpie[_user][pool.market] += absVal;
                } else {
                    uint256 absVal = uint256(-weight);
                    pool.totalVoteInVlPenpie -= absVal;
                    userVotedForPoolInVlPenpie[_user][pool.market] -= absVal;
                }
            }

            _afterVoteUpdate(_user, pool.market, _userVotes[i].pid, weight);
        }
        
        // update user's total vote and all vlPNP vote
        if (totalUserVote > 0) {
            userTotalVotedInVlPenpie[_user] += uint256(totalUserVote);
            totalVlPenpieInVote += uint256(totalUserVote);
        } else {
            userTotalVotedInVlPenpie[_user] -= uint256(-totalUserVote);
            totalVlPenpieInVote -= uint256(-totalUserVote);
        }
    }

    // for sub inheretence to add customized logic
    function _afterVoteUpdate(address _user, address _market, uint256 _pid, int256 _weight) internal virtual {
        uint256 epoch = IPenpieBribeManager(bribeManager).exactCurrentEpoch();
        emit Voted(epoch, _user, _market, _pid, _weight);
    }

    /* ============ Admin Functions ============ */

	function pause() public onlyOwner {
		_pause();
	}

	function unpause() public onlyOwner {
		_unpause();
	}

    function setBribeManager(address _bribeManager) external onlyOwner {
        bribeManager = _bribeManager;
        emit BribeManagerSet(_bribeManager);
    }

    function addPool(
        address _market,
        uint256  _chainId
    ) external onlyBribeManager {
        if (_market == address(0)) revert ZeroAddressError();
        Pool memory pool = Pool({
            market: _market,
            totalVoteInVlPenpie: 0,
            chainId: _chainId,
            isActive: true
        });
        poolInfos.push(pool);
        
        marketToPid[_market] = poolInfos.length -1 ;
        
        emit AddPool(_market, poolInfos.length - 1);
    }

    function removePool(uint256 _index) external onlyBribeManager {
        if (_index >= poolInfos.length) revert OutOfPoolIndex();
        poolInfos[_index].isActive = false;

        emit DeactivatePool(poolInfos[_index].market, _index);
    }

    function updatePool(uint256 _pid, uint256 _chainId, address _market, bool _active) external onlyOwner {
        if (_pid >= poolInfos.length) revert InvalidPool();
        Pool storage pool = poolInfos[_pid];
        pool.market = _market;
        pool.chainId = _chainId;
        pool.isActive = _active;
        emit UpdatePool(_pid, _chainId, _market, _active);
    }

    function forceSetMarketPID(address _market, uint256 _newPid) external onlyOwner {
        marketToPid[_market] = _newPid;
        emit MarketPIDForceSet(_market, _newPid);
    }

    function forcePopLastPool() external onlyOwner {
        if (poolInfos.length == 0) revert OutOfPoolIndex();
        poolInfos.pop();
    }

    function updateAllowedOperator(address _user, bool _allowed) external onlyOwner {
        allowedOperator[_user] = _allowed;

        emit UpdateOperatorStatus(_user, _allowed);
    }
}
