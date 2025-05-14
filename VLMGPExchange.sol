// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ILocker.sol";
import "./interfaces/IPRTAirdrop.sol";
import "./interfaces/IMintableERC20.sol";

/// @title VLMGPExchange
/// @author Magpie Team
/// @notice This contract is the main contract that user will exchange PRT tokens for vlmgp for the users.

contract VLMGPExchange is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    address public PRT;
    ILocker public vlMGP;
    address public PRTAirdrop;
    address public MGP;

    uint256 public phaseOneStartTime;
    uint256 public phaseTwoStartTime;
    uint256 public phaseThreeStartTime;
    uint256 public constant currentExchangeRate = 10; // 1 PRT => 10 vlMGP

    mapping(address => uint256) public exchangedPRT;

    /* ============ Events ============ */

    event Exchanged(address indexed _user, uint256 _prtAmount, uint256 _vlMgpAmount);

    /* ============ Errors ============ */

    error InvalidPhase();
    error ExceedsMaxExchangeable();
    error InsufficientVlMGP();

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function __vlMGPExchange_init(
        address _PRT,
        address _vlMGP,
        address _PRTAirdrop,
        address _MGP,
        uint256 _phaseOneStartTime,
        uint256 _phaseTwoStartTime,
        uint256 _phaseThreeStartTime
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        PRT = _PRT;
        vlMGP = ILocker(_vlMGP);
        PRTAirdrop = _PRTAirdrop;
        MGP = _MGP;
        phaseOneStartTime = _phaseOneStartTime;
        phaseTwoStartTime = _phaseTwoStartTime;
        phaseThreeStartTime = _phaseThreeStartTime;
    }

    /* ============ External Functions ============ */

    function exchangePRTforVlMGP(uint256 prtAmount) external whenNotPaused nonReentrant {
        if(prtAmount > quoteMaxExchangeForUser(msg.sender)) revert ExceedsMaxExchangeable();
        if(prtAmount > maxPRTByLeftMGP()) revert InsufficientVlMGP(); 

        uint256 vlMgpAmount = currentExchangeRate * (prtAmount * (10 ** IMintableERC20(address(vlMGP)).decimals())) / (10 ** IMintableERC20(PRT).decimals());
        
        exchangedPRT[msg.sender] += prtAmount;

        IMintableERC20(PRT).burn(msg.sender, prtAmount);

        IERC20(MGP).safeApprove(address(vlMGP), vlMgpAmount);
        ILocker(vlMGP).lockFor(vlMgpAmount, msg.sender);

        emit Exchanged(msg.sender, prtAmount, vlMgpAmount);
    }

    function quoteMaxExchangeForUser(address _user) public view returns(uint256) {
        uint256 maxExchangeable;
        uint256 claimedAmount = IPRTAirdrop(PRTAirdrop).getClaimed(_user);

        maxExchangeable = claimedAmount * currentConvertPercent() / 100;

        return (maxExchangeable - exchangedPRT[_user]);
    }

    function maxPRTByLeftMGP() public view returns(uint256) {
        uint256 maxPrt = ((IERC20(MGP).balanceOf(address(this)) * (10 ** IMintableERC20(PRT).decimals())) / (10 ** IMintableERC20(address(vlMGP)).decimals())) / currentExchangeRate;
        return maxPrt;
    }

    function currentConvertPercent() public view returns(uint256) {
        uint256 currentTime = block.timestamp;

        if (currentTime >= phaseThreeStartTime) {
            revert InvalidPhase();
        } else if (currentTime >= phaseTwoStartTime) {
            return 30;
        } else if (currentTime >= phaseOneStartTime) {
            return 12;
        } else {
            revert InvalidPhase();
        }
    }
 
    /* ============ Admin Functions ============ */

    function adminWithdrawTokens(address _token) external onlyOwner {
        IERC20(_token).safeTransfer(owner(), IERC20(_token).balanceOf((address(this))));
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }	

}


