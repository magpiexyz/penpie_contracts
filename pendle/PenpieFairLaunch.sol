// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract PenpieFairLaunch is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    struct UserInfo {
        uint256 deposit;
        uint256 fundReturned;
    }

    IERC20 public principalToken;

    uint256 public totalAmountRaised;
    uint256 public totalAmountToRaise;
    uint32 public startTimestamp;
    uint32 public endTimestamp;

    bytes32 public maxMerkleRoot;

    mapping(address => UserInfo) public userInfos;

    /* ============ Events ============ */

    event Deposit(address indexed _user, uint256 _amount);
    event Refund(address indexed _user, uint256 _amount);

    /* ============ Errors ============ */

    error InvalidTime();
    error InvalidAmount();
    error NoRefund1();
    error NoRefund2();
    error ShouldDuring();
    error ShouldAfter();
    error ShouldBefore();
    error InvalidRoot();
    error BeyondMaxAlloc();

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __PendleRush_init(
        address _token,
        uint256 _raiseTarget,
        uint32 _startTimestamp,
        uint32 _endTimestamp,
        bytes32 _maxMerkleRoot
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        principalToken = IERC20(_token);
        totalAmountToRaise = _raiseTarget;
        startTimestamp = _startTimestamp;
        endTimestamp = _endTimestamp;
        maxMerkleRoot = _maxMerkleRoot;
    }

    receive() external payable {}

    /* ============ Modifier ============ */

    modifier _checkDuring() {
        if (
            block.timestamp <= startTimestamp || block.timestamp >= endTimestamp
        ) revert ShouldDuring();
        _;
    }

    modifier _checkEnds() {
        if (block.timestamp <= endTimestamp) revert ShouldAfter();
        _;
    }

    modifier _checkBefore() {
        if (block.timestamp >= startTimestamp) revert ShouldBefore();
        _;
    }

    /* ============ External Read Functions ============ */

    function getMaxWithdrawableBalance() public view returns (uint256) {
        if (totalAmountToRaise >= totalAmountRaised) {
            return totalAmountRaised;
        } else {
            return totalAmountToRaise;
        }
    }

    function verifyProof(
        address _account,
        uint256 _maxAmount,
        bytes32[] calldata merkleProof
    ) public view returns (bool) {
        bytes32 node = keccak256(abi.encodePacked(_account, _maxAmount));
        return MerkleProof.verify(merkleProof, maxMerkleRoot, node);
    }

    // ============= Exeternal Write Functions =================

    function participate(
        uint256 _amount,
        uint256 _maxAmount,
        bytes32[] calldata merkleProof
    ) external _checkDuring whenNotPaused nonReentrant {
        if (!verifyProof(msg.sender, _maxAmount, merkleProof))
            revert InvalidRoot();
        if (_amount == 0) revert InvalidAmount();

        UserInfo storage userInfo = userInfos[msg.sender];
        if (userInfo.deposit + _amount > _maxAmount) revert BeyondMaxAlloc();

        principalToken.transferFrom(msg.sender, address(this), _amount);

        userInfo.deposit += _amount;
        totalAmountRaised += _amount;

        emit Deposit(msg.sender, _amount);
    }

    function returnExcessAmount() external _checkEnds nonReentrant {
        if (totalAmountToRaise > totalAmountRaised) revert NoRefund1();

        UserInfo storage userInfo = userInfos[msg.sender];
        if (userInfo.fundReturned != 0) revert NoRefund2();

        uint256 diff = totalAmountRaised - totalAmountToRaise;
        uint256 returnAmount = (diff * userInfo.deposit) / totalAmountRaised;
        userInfo.fundReturned = returnAmount;

        principalToken.safeTransfer(msg.sender, returnAmount);

        emit Refund(msg.sender, returnAmount);
    }

    /* ============ Admin Functions ============ */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdrawRaisedAmount()
        external
        _checkEnds
        onlyOwner
        returns (uint256)
    {
        uint256 balance = getMaxWithdrawableBalance();
        principalToken.transfer(msg.sender, balance);
        return balance;
    }

    function updateTimeInfo(
        uint32 _startTime,
        uint32 _endTime
    ) external _checkBefore onlyOwner {
        if (_startTime < block.timestamp || _endTime < block.timestamp)
            revert InvalidTime();

        startTimestamp = _startTime;
        endTimestamp = _endTime;
    }
}
