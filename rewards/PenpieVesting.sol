// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import { PausableUpgradeable } from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

import "../interfaces/IVLPenpie.sol";

contract PenpieVesting is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    uint256 public startVestingTime;
    uint256 public vestingPeriodCount;
    uint256 public intervals;

    mapping(address => uint256) private claimedAmount;

    IERC20 public PNP;
    IERC20 public rPNP;
    IVLPenpie public vlpnp;

    /* ============ Events ============ */

    event ClaimEvent(address account, uint256 amount, bool isLock);

    /* ============ Errors ============ */

    error NotStarted();
    error RPNPNotSet();
    error LockerNotSet();

    /* ============ Constructor ============ */

    function __PenpieVesting_init(
        IERC20 _pnp,
        IERC20 _rPNP,
        address _vlpnp,
        uint256 _startVestingTime,
        uint256 _vestingPeriodCount,
        uint256 _intervals
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        PNP = _pnp;
        rPNP = _rPNP;
        startVestingTime = _startVestingTime;
        vestingPeriodCount = _vestingPeriodCount;
        intervals = _intervals;
        vlpnp = IVLPenpie(_vlpnp);
    }

    /* ============ External Getters ============ */

    function getClaimed(address account) public view returns (uint256) {
        return claimedAmount[account];
    }

    function getClaimable(address account) public view returns (uint256) {
        if (address(rPNP) == address(0)) revert RPNPNotSet();
        if (block.timestamp < startVestingTime) {
            return 0;
        }

        uint256 claimed = claimedAmount[account];
        uint256 granted = rPNP.balanceOf(account);

        if (claimed >= granted) {
            return 0;
        }

        uint256 vested = granted * ((block.timestamp - startVestingTime) / intervals) / (vestingPeriodCount);
        if (vested > granted) {
            return granted - claimed;
        }

        return vested - claimed;
    }

    /* ============ External Functions ============ */

    function claim(bool isLock) external whenNotPaused nonReentrant {
        if (block.timestamp < startVestingTime) revert NotStarted();

        //Verify the merkle proof.

        uint256 claimable = getClaimable(msg.sender);

        // Mark it claimed and send the token.
        if (isLock) {
            if (address(vlpnp) == address(0)) revert LockerNotSet();
            PNP.safeApprove(address(vlpnp), claimable);
            vlpnp.lockFor(claimable, msg.sender);
        } else {
            PNP.safeTransfer(msg.sender, claimable);
        }
        uint256 userClaimedAmount = claimedAmount[msg.sender];
        claimedAmount[msg.sender] = userClaimedAmount + claimable;
        emit ClaimEvent(msg.sender, claimable, isLock);
    }

    /* ============ Admin functions ============ */

    function configure(address _vlpnp, address _rPNP) external onlyOwner {
        vlpnp = IVLPenpie(_vlpnp);
        rPNP = IERC20(_rPNP);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
