// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract PRTAirdrop is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    bytes32 public totalRewardMerkleRoot;
    uint256 public startAirdropTime;

    mapping(address => uint256) public claimedAmount;

    IERC20 public reward;

    /* ============ Events ============ */

    event ClaimEvent(address account, uint256 amount);
    event AirdropConfigUpdated(
        uint256 startAirdropTime,
        bytes32 totalRewardMerkleRoot
    );
    event EmergencyWithdrawn(address to, uint256 amount);

    /* ============ Errors ============ */

    error NotStarted();
    error InvalidProof();
    error AlreadyClaimed();

    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _reward,
        uint256 _startAirdropTime,
        bytes32 _totalRewardMerkleRoot
    ) external initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        reward = IERC20(_reward);
        totalRewardMerkleRoot = _totalRewardMerkleRoot;
        startAirdropTime = _startAirdropTime;
    }

    /* ============ External Getters ============ */

    function getClaimed(address account) public view returns (uint256) {
        return claimedAmount[account];
    }

    function getClaimable(
        address account,
        uint256 totalAmount,
        bytes32[] calldata merkleProof
    ) public view returns (uint256) {
        if (
            block.timestamp < startAirdropTime ||
            getClaimed(account) >= totalAmount
        ) {
            return 0;
        }

        if (!verifyProof(account, totalAmount, merkleProof)) {
            revert InvalidProof();
        }

        return totalAmount - getClaimed(account);
    }

    function verifyProof(
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) public view returns (bool) {
        bytes32 node = keccak256(abi.encodePacked(account, amount));
        return MerkleProof.verify(merkleProof, totalRewardMerkleRoot, node);
    }

    /* ============ External Functions ============ */

    function claim(
        uint256 totalAmount,
        bytes32[] calldata merkleProof
    ) external whenNotPaused nonReentrant {
        if (block.timestamp < startAirdropTime) revert NotStarted();

        // Verify the merkle proof and get claimable amount
        uint256 claimable = getClaimable(msg.sender, totalAmount, merkleProof);

        if (claimable == 0) revert AlreadyClaimed();

        claimedAmount[msg.sender] += claimable;
        reward.safeTransfer(msg.sender, claimable);
        emit ClaimEvent(msg.sender, claimable);
    }

    /* ============ Admin functions ============ */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdraw() external onlyOwner whenPaused {
        uint256 amountToWithdraw = reward.balanceOf(address(this));
        reward.safeTransfer(msg.sender, amountToWithdraw);
        emit EmergencyWithdrawn(msg.sender, amountToWithdraw);
    }

    function config(
        uint256 _startAirdropTime,
        bytes32 _totalRewardMerkleRoot
    ) external onlyOwner {
        startAirdropTime = _startAirdropTime;
        totalRewardMerkleRoot = _totalRewardMerkleRoot;
        emit AirdropConfigUpdated(_startAirdropTime, _totalRewardMerkleRoot);
    }
}