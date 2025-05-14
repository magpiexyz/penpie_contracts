// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

/// @title DutchAuction
/// @author Magpie Team, an Dutch Auction contrat for allocate bidToken against projectToken.

contract DutchAuction is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    struct UserInfo {
        uint256 userBidAmount;
        uint256 userClaimedProjectToken;
    }

    address public projectToken; // Address of projectToken token for sale
    address public bidToken; // Address of token used for purchase project token
    uint256 public totalBidAmount; // Total bidAmount, in bid token decimal
    uint256 public totalProjectToBid;// total Project token To bid, in project token decimal
    bool public claimPhaseStart;

    uint256 public auctionStartTime; // Timestamp for the start of the auction.
    uint256 public startingPrice; // Starting price of projectToken. Number of bid token per project tokens.(Stored by considering bidToken decimals).
    uint256 public minPrice; // Minimum price (floor). Mean price of bid token per project token. (Stored by considering bidToken decimals).

    uint256 public priceInterval; // Price (project token per bidToken) deduction interval in seconds. 
    uint256 public priceDecrementPrcnt; // price decrease every interval in percentage  (Stored by multipling with DENOMINATOR)

    uint256 public cliffEndTime; //Time of ending cliff duration. start when admin decide to start claim
    uint256 public vestingPeriodDuration; // vesting period duration
    uint256 public vestingPercentage; // percentage of project token usder vesting period on claim
    
    uint256 public projectTokenDecimals;
    uint256 public bidTokenDecimals;

    uint256 constant DENOMINATOR = 10000;

    mapping(address => UserInfo) public userInfos;

    /* ============ Events ============ */

    event BidPlaced(address indexed bidder, uint256 auctionPrice, uint256 bidTokenAmount);
    event ClaimedProjectToken(address indexed bidder, uint256 projectTokenAmount);
    event ConfiguredNewData(
        uint256 startingPrice, uint256 minPrice, uint256 priceInterval, uint256 priceDecrementPrcnt, uint256 auctionStartTime
    );
    event ConfigureNewVestingData(uint256 vestingPeriodDura, uint256 vestingPercentage);
    event StartedClaim(bool isClaimStart, uint256 vestingCliffPeriod, uint256 cliffEndTime);

    /* ============ Errors ============ */

    error ClaimPhaseNotStart();
    error PriceUpdated();
    error AuctionAlreadyEnded();
    error BidAmountMustBeGreaterThanZero();
    error NotEnoughProjectTokensForSale();
    error AuctionNotStartedAt();
    error NoMoreClaimbleProjectTokens();
    error StartPriceCanNotLowerThanMinPrice();
    error NotValidPriceDecrementPrcnt();
    error NotValidAuctionStartTime();
    error AuctionNotEndedAt();
    error canNotCofigAfterAuctionStart();
    error ZeroAddressNotAllowed();

    /* ============ Constructor ============ */

    constructor() {
        _disableInitializers();
    }

    function _DutchAuction_init(
        address _projectToken,
        address _bidToken,
        uint256 _totalProjectToBid,
        uint256 _startingPrice,
        uint256 _minPrice,
        uint256 _priceInterval,
        uint256 _priceDecrementPrcnt,
        uint256 _AuctionStartTime
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        if (_projectToken == address(0) || _bidToken == address(0)) revert ZeroAddressNotAllowed();
        projectToken = _projectToken;
        bidToken = _bidToken;
        totalProjectToBid = _totalProjectToBid;
        startingPrice = _startingPrice;
        minPrice = _minPrice;
        priceInterval = _priceInterval;
        priceDecrementPrcnt = _priceDecrementPrcnt;
        auctionStartTime = _AuctionStartTime;
        projectTokenDecimals = ERC20(projectToken).decimals();
        bidTokenDecimals = ERC20(bidToken).decimals();
    }

    /* ============ Modifier ============ */

    modifier auctionOngoing() {
        if (isAuctionEnd()) revert AuctionAlreadyEnded();
        if (block.timestamp < auctionStartTime) revert AuctionNotStartedAt();
        _;
    }

    /* ============ External Read Functions ============ */

    //Price is by cosidering bid token decimals
    function clearingPrice() public view returns (uint256) {
        if (totalBidAmount == 0) return minPrice;

        uint256 _clearingPrice = (totalBidAmount * (10 ** projectTokenDecimals)) / totalProjectToBid ;
        return _clearingPrice  < minPrice ? minPrice : _clearingPrice;
    }

    // current auction price of bidtoken per project token by considering bidtoken decimal.
    function currentAuctionPrice() public view returns (uint256) {
        if (block.timestamp < auctionStartTime) return startingPrice;

        uint256 intervalPasssed = (block.timestamp - auctionStartTime) / priceInterval;
        uint256 priceDecrementAmount = (priceDecrementPrcnt * startingPrice) / DENOMINATOR;
        uint256 priceReduction = intervalPasssed * priceDecrementAmount;

        return (startingPrice - minPrice) <= priceReduction ? minPrice : startingPrice - priceReduction;
    }

    function isAuctionEnd() public view returns (bool) {
        return currentAuctionPrice() <= clearingPrice() || quoteMaxBidAmount() == 0;
    }

    // max bid would be making clearing price at current auction price
    function quoteMaxBidAmount() public view returns (uint256) {
        uint256 curPrice = currentAuctionPrice();
        if(curPrice <= clearingPrice()) return 0;
        
        return ((totalProjectToBid * curPrice ) / (10 ** projectTokenDecimals)) - totalBidAmount; // Need to devide with project token decimals as bid token and allocated project token have different decimals 
    }

    function getClaimable(address account) public view returns (uint256 claimableAmount) {
        UserInfo storage userInfo = userInfos[account];
        uint256 userAllocated = (userInfo.userBidAmount * (10 ** projectTokenDecimals))  / clearingPrice();  

        if (userAllocated > 0 && cliffEndTime != 0) {
            uint256 nonVestedAmount = userAllocated * (DENOMINATOR - vestingPercentage) / DENOMINATOR;
            uint256 vestedAmount = 0;
            if (block.timestamp >= cliffEndTime) {
                uint256 totalVestingAmount = userAllocated - nonVestedAmount;
                vestedAmount = (block.timestamp - cliffEndTime) * totalVestingAmount / vestingPeriodDuration;
                if (vestedAmount >= totalVestingAmount) {
                    vestedAmount = totalVestingAmount;
                }
            }

            claimableAmount = nonVestedAmount + vestedAmount - userInfo.userClaimedProjectToken;
        }
    }

    function getUserInfo(address account)
        public
        view
        returns (
            uint256 userBidAmount,
            uint256 userAllocatedAmount,
            uint256 userClaimableAmount,
            uint256 userClaimedAmount
        )
    {
        UserInfo memory userInfo = userInfos[account];
        userBidAmount = userInfo.userBidAmount;
        userAllocatedAmount = (userInfo.userBidAmount * 10 ** projectTokenDecimals) / clearingPrice();  
        userClaimableAmount = getClaimable(account);
        userClaimedAmount = userInfo.userClaimedProjectToken;
    }

    /* ============ External Write Functions ============ */

    function placeBid(uint256 bidAmount, uint256 auctionPrice) external whenNotPaused nonReentrant auctionOngoing {
        if (bidAmount > quoteMaxBidAmount()) revert NotEnoughProjectTokensForSale();
        if (auctionPrice != currentAuctionPrice()) revert PriceUpdated();
        if (bidAmount == 0) revert BidAmountMustBeGreaterThanZero();

        userInfos[msg.sender].userBidAmount += bidAmount;
        totalBidAmount += bidAmount;
    
        emit BidPlaced(msg.sender, auctionPrice, bidAmount);

        IERC20(bidToken).safeTransferFrom(msg.sender, address(this), bidAmount);
    }

    function ClaimProjectToken() external whenNotPaused nonReentrant {
        if (!claimPhaseStart) revert ClaimPhaseNotStart();
        uint256 claimableAmount = getClaimable(msg.sender);
        if (claimableAmount == 0) revert NoMoreClaimbleProjectTokens();

        userInfos[msg.sender].userClaimedProjectToken += claimableAmount;
        IERC20(projectToken).safeTransfer(msg.sender, claimableAmount);

        emit ClaimedProjectToken(msg.sender, claimableAmount);
    }

    /* ============ Admin Functions ============ */

    function config(
        uint256 _startingPrice,
        uint256 _minPrice,
        uint256 _priceInterval,
        uint256 _priceDecrementPrcnt,
        uint256 _AuctionStartTime
    ) external onlyOwner {
        if(block.timestamp > auctionStartTime) revert canNotCofigAfterAuctionStart();
        if(_startingPrice < _minPrice) revert StartPriceCanNotLowerThanMinPrice();
        if(_priceDecrementPrcnt >= DENOMINATOR) revert NotValidPriceDecrementPrcnt();
        if(_AuctionStartTime < block.timestamp) revert NotValidAuctionStartTime();
        startingPrice = _startingPrice;
        minPrice = _minPrice;
        priceInterval = _priceInterval;
        priceDecrementPrcnt = _priceDecrementPrcnt;
        auctionStartTime = _AuctionStartTime;

        emit ConfiguredNewData(startingPrice, minPrice, priceInterval, _priceDecrementPrcnt, auctionStartTime);
    }

    function setVestingData(uint256 _vestingPeriodDuration, uint256 _vestingPercentage)
        external
        onlyOwner
    {
        vestingPeriodDuration = _vestingPeriodDuration;
        vestingPercentage = _vestingPercentage;

        emit ConfigureNewVestingData(vestingPeriodDuration, vestingPercentage);
    }

    function startClaim(bool isClaimStart, uint256 _vestingCliffPeriod) external onlyOwner {
        claimPhaseStart = isClaimStart;
        cliffEndTime = block.timestamp + _vestingCliffPeriod;
        emit StartedClaim(claimPhaseStart, _vestingCliffPeriod, cliffEndTime);
    }

    function withdrawBidTokens() external onlyOwner nonReentrant {
        if(!isAuctionEnd()) revert AuctionNotEndedAt();
        uint256 balancebidToken = IERC20(bidToken).balanceOf(address(this));
        IERC20(bidToken).safeTransfer(msg.sender, balancebidToken);
    }

    function withdrawUnsoldProjectToken() external onlyOwner nonReentrant {
        if(!isAuctionEnd()) revert AuctionNotEndedAt();
        uint256 balanceOfProjectToken = IERC20(projectToken).balanceOf(address(this));
        IERC20(projectToken).safeTransfer(msg.sender, balanceOfProjectToken);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
