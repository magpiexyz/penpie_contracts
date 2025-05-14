// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "@pendle/core-v2/contracts/core/StandardizedYield/SYBaseWithRewardsUpg.sol";
import "../../interfaces/ISmartPendleConvert.sol";
import "../../interfaces/IMasterPenpie.sol";
import "../../interfaces/pancakeswap/IStableSwapRouter.sol";
import "../../interfaces/pancakeswap/IPancakeStableSwapTwoPool.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MPendleSY is SYBaseWithRewardsUpg {
    using SafeERC20 for IERC20;

    address public immutable Pendle;
    address public immutable mPendle;
    address public immutable PNP;
    address public immutable mPendleReceiptToken;
    address public immutable mPendlePenpieRewarder;
    address public immutable masterPenpie;
    address public immutable pancakeRouter;
    address public immutable pendleMPendlePool;
    ISmartPendleConvert public immutable smartPendleConvertor;
    uint256 public constant STAKEMODE = 1;
    mapping(address => bool) public allowedPauser;
    uint256 public constant DENOMINATOR = 10000;
    uint256 public constant Pendle_Index = 0;
    uint256 public constant MPendle_Index = 1;

    /* ============ Constructor ============ */
    constructor (
        address _Pendle,
        address _mPendle,
        address _PNP,
        address _mPendleReceiptToken,
        address _smartPendleConvertor,
        address _mPendlePenpieRewarder ) SYBaseUpg(_mPendle) {

        _disableInitializers();
        Pendle = _Pendle;
        mPendle = _mPendle;
        PNP = _PNP;
        smartPendleConvertor = ISmartPendleConvert(_smartPendleConvertor);
        mPendleReceiptToken = _mPendleReceiptToken;
        mPendlePenpieRewarder = _mPendlePenpieRewarder;

        masterPenpie = smartPendleConvertor.masterPenpie();
        pancakeRouter = smartPendleConvertor.router();
        pendleMPendlePool = smartPendleConvertor.pendleMPendlePool();
           
    }   

    function initialize(string calldata name, string calldata symbol) external initializer {
        __SYBaseUpg_init(name, symbol);
        _safeApproveInf(mPendle, masterPenpie);
        _safeApproveInf(Pendle, address(smartPendleConvertor));
    } 

    /* ====================== Errors ================= */
    error OnlyPauser();

    /* =====================Events =================== */
    event UpdatePauserStatus(address indexed _pauser, bool _allowed);

    /* ================= Modifiers =================== */
    modifier onlyPauser() {
        if (!allowedPauser[msg.sender]) revert OnlyPauser();
        _;
    }

    /**
     * @notice mint shares based on the deposited base tokens
     * @param tokenIn token address to be deposited
     * @param amountToDeposit amount of tokens to deposit
     * @return amountSharesOut amount of shares minted
     */
    function _deposit(
        address tokenIn,
        uint256 amountToDeposit
    ) internal virtual override returns (uint256 amountSharesOut) {
        
        if(tokenIn == Pendle)
            _harvestAndCompound(amountToDeposit); 
        else
            _harvestAndCompound(0);

        uint256 mPendleReceiptReceived = 0;
        if (tokenIn == Pendle) {
            mPendleReceiptReceived = smartPendleConvertor.smartConvert(amountToDeposit, STAKEMODE); // will convert and stake.
        } else if (tokenIn == mPendle) {
            IMasterPenpie(masterPenpie).deposit(mPendle, amountToDeposit);
            mPendleReceiptReceived = amountToDeposit;
        } else if (tokenIn == mPendleReceiptToken){
            mPendleReceiptReceived = amountToDeposit; 
        }

        // Using total assets before deposit as shares not minted yet
        (uint256 totalAsset,) = IMasterPenpie(masterPenpie).stakingInfo(mPendle, address(this));
        amountSharesOut = _calcSharesOut(mPendleReceiptReceived, totalSupply(), totalAsset - mPendleReceiptReceived);
    }

    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 amountTokenOut) {

        _harvestAndCompound(0);
        (uint256 totalAsset,) = IMasterPenpie(masterPenpie).stakingInfo(mPendle, address(this));

        uint256 priorTotalSupply = totalSupply() + amountSharesToRedeem;
        amountTokenOut = amountSharesToRedeem * totalAsset / priorTotalSupply; 
        
        // just in case some math might cause 0.001% less for the very last person withdraw
        uint256 mPendleReceiptSelfBalance = _selfBalance(mPendleReceiptToken);
        if (amountTokenOut > mPendleReceiptSelfBalance)
            amountTokenOut = mPendleReceiptSelfBalance;

        if (tokenOut == mPendle){
            IMasterPenpie(masterPenpie).withdraw(mPendle, amountTokenOut); // withdraw mPendle from penpie
            _transferOut(tokenOut, receiver, amountTokenOut);
        } else if (tokenOut == mPendleReceiptToken) {
            _transferOut(tokenOut, receiver, amountTokenOut);
        } else if (tokenOut == Pendle) { 
            IMasterPenpie(masterPenpie).withdraw(mPendle, amountTokenOut); // withdraw mPendle from penpie
            amountTokenOut = _swapMPendleForPendle(amountTokenOut, receiver);// swap mPendle for Pendle on pancake swap and send to receiver
        }

    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IStandardizedYield-exchangeRate}
     */

    function exchangeRate() public view virtual override returns (uint256) {
        return getTotalAssetOwned() * (1e18) / totalSupply(); 
    }

    function getTotalAssetOwned() public view returns (uint256 totalAssetOwned) {
        (totalAssetOwned,) = IMasterPenpie(masterPenpie).stakingInfo(mPendle, address(this));
        (,,,uint256 unclaimedAmount) = IMasterPenpie(masterPenpie).pendingTokens(mPendle, address(this), Pendle);

        if (unclaimedAmount > 0)
            totalAssetOwned += previewPendleTomPendleConvert(unclaimedAmount);
    }

    /*///////////////////////////////////////////////////////////////
                            Swap with PCS Stable Swap Router
    //////////////////////////////////////////////////////////////*/

    function _swapMPendleForPendle(
        uint256 amtmPendleToSwap, address receiver
    ) internal virtual returns(uint256 pendleReceived){

        address[] memory tokenPath = new address[](2);
        uint256[] memory flag = new uint256[](1);

        tokenPath[0] = mPendle;
        tokenPath[1] = Pendle;
        flag[0] = 2;

        IERC20(mPendle).approve(pancakeRouter, amtmPendleToSwap);
        pendleReceived = IStableSwapRouter(pancakeRouter).exactInputStableSwap(
            tokenPath,
            flag, 
            amtmPendleToSwap, 
            0, 
            receiver
        );
    }     

    /*///////////////////////////////////////////////////////////////
                            AUTOCOMPOUND FEATURE
    //////////////////////////////////////////////////////////////*/

    function harvestAndCompound() external whenNotPaused nonReentrant {
        _harvestAndCompound(0);
    }

    function _harvestAndCompound(uint256 amountPendleToNotCompound) internal {

        (uint256 pendingPNP,,,uint256 pendingPendle) = IMasterPenpie(masterPenpie).pendingTokens(mPendle, address(this), Pendle);
        if(pendingPNP > 0 || pendingPendle > 0){ // Don't harvest and compound if non PNP or Pendle rewards
            address[] memory stakingToken = new address[](1);
            stakingToken[0] = mPendle;
            IMasterPenpie(masterPenpie).multiclaim(stakingToken); // PNP and PENDLE should both be claimed from Penpie
            uint256 amountPendleToCompound = _selfBalance(Pendle) - amountPendleToNotCompound; // so we don't compound PENDLE that is to be Deposited 

            if (amountPendleToCompound > 0) {
                smartPendleConvertor.smartConvert(amountPendleToCompound, STAKEMODE);// will convert and stake.
            }
        }
    }

    /*///////////////////////////////////////////////////////////////
                               REWARDS-RELATED
    //////////////////////////////////////////////////////////////*/


    /**
     * @dev See {IStandardizedYield-getRewardTokens}
     */

    function _getRewardTokens() internal view override returns (address[] memory res) {
        res = new address[](1);
        res[0] = PNP;
        // only PNP, PENDLE always compounded
    }

    function _redeemExternalReward() internal override {
        _harvestAndCompound(0); // Pendle reward from Penpie should be compound while PNP remains.
    }


    /*///////////////////////////////////////////////////////////////
                    PREVIEW-RELATED
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 amountSharesOut) {

        uint256 totalAsset = getTotalAssetOwned();

        if(tokenIn == mPendle || tokenIn == mPendleReceiptToken) {
            amountSharesOut = _calcSharesOut(amountTokenToDeposit, totalSupply(), totalAsset);
        } else if (tokenIn == Pendle) {
            uint256 mPendleReceived = previewPendleTomPendleConvert(amountTokenToDeposit);
            amountSharesOut = _calcSharesOut(mPendleReceived, totalSupply(), totalAsset);
        }
    }

    function previewPendleTomPendleConvert(
        uint256 amountPendleToConvert
    ) internal view  returns (uint256 mPendleToReceive) {
        uint256 convertRatio = DENOMINATOR;
        uint256 mPendleToPendle = smartPendleConvertor.currentRatio();

        if (mPendleToPendle < smartPendleConvertor.buybackThreshold()) {
            uint256 maxSwap = smartPendleConvertor.maxSwapAmount();
            uint256 amountToSwap = amountPendleToConvert > maxSwap ? maxSwap : amountPendleToConvert;
            uint256 convertAmount = amountPendleToConvert - amountToSwap;
            convertRatio = (convertAmount * DENOMINATOR) / amountPendleToConvert;
        }

        mPendleToReceive=smartPendleConvertor.estimateTotalConversion(amountPendleToConvert, convertRatio);
    }

    function _previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 amountTokenOut) {

        uint256 totalAsset = getTotalAssetOwned();
        uint256 mPendleOut = amountSharesToRedeem * totalAsset / totalSupply();

        if (tokenOut == mPendle || tokenOut == mPendleReceiptToken) {
            amountTokenOut = mPendleOut;
        } else if (tokenOut == Pendle) {
            (uint256 pendleOut) = IPancakeStableSwapTwoPool(pendleMPendlePool).get_dy(MPendle_Index, Pendle_Index, mPendleOut);
            amountTokenOut = pendleOut;
        } 
    }

    function _calcSharesOut(
        uint256 _mPendleReceiptReceived,
        uint256 _totalSupply,
        uint256 _totalAssetPrior
    ) internal virtual view returns (uint256){
        if (_totalAssetPrior == 0 || _totalSupply == 0)
            return _mPendleReceiptReceived;
        else
            return _mPendleReceiptReceived * _totalSupply / _totalAssetPrior;
    }    

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals){
        return (AssetType.TOKEN, mPendle, IERC20Metadata(mPendle).decimals());
    }

    function getTokensIn() public view virtual override returns (address[] memory res){
        res = new address[](3);
        res[0] = Pendle;
        res[1] = mPendle;
        res[2] = mPendleReceiptToken;   
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        res = new address[](3);
        res[0] = mPendle;
        res[1] = Pendle;
        res[2] = mPendleReceiptToken;
    }
    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == mPendle || token == Pendle || token == mPendleReceiptToken;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == mPendle || token == Pendle || token == mPendleReceiptToken;
    }
    /*///////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function updateAllowedPauser(address _pauser, bool _allowed) external onlyOwner {
        allowedPauser[_pauser] = _allowed;

        emit UpdatePauserStatus(_pauser, _allowed);
    }

    function pauseByWhitelisted() external onlyPauser {
        _pause();
    }

}