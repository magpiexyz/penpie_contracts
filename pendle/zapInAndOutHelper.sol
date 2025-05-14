// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { IPendleMarketDepositHelper } from "../interfaces/pendle/IPendleMarketDepositHelper.sol";
import { IPendleStaking } from "../interfaces/IPendleStaking.sol";
import { IPendleRouterV4 } from "../interfaces/pendle/IPendleRouterV4.sol";
import {IPendleStakingReader} from "../interfaces/penpieReader/IPendleStakingReader.sol";

contract zapInAndOutHelper is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ State Variables ============ */

    address public kyberSwapRouter;
    address public pendleSwap;
    address private constant ADDREESS_ZERO = address(0);

    
    /* ============ Structs ============ */

    struct tokenZapInData {
        address market;
        address tokenInToZap;
        uint256 tokenAmount;
        address baseToken;
        uint256 minTokenOut;
        bool needScale;
    }

    struct tokenZapOutData {
        address market;
        address tokenForZapOut;
        uint256 tokenAmount;
        address baseToken;
        uint256 minTokenOut;
        bool needScale;
    }

    /* ============ State Variables ============ */

    IPendleMarketDepositHelper public pendleMarketDepositHelper;
    IPendleRouterV4 public pendleRouterV4;
    IPendleStaking public pendleStaking;

    /* ============ Events ============ */

    event zapInToPendleMarket(address user, uint256 tokenAmountIn, address market, uint256 marketTokenAmountOut);
    event zapOutFromPendleMarket(address user, uint256 tokenAmountOutInMarketReceipttoken, address market, address tokenOut, uint256 tokenOutAmount);
    event kyberSwapRouterUpdated(address _kyberSwapRouter);
    event pendleSwapUpdated(address _pendleSwap);
    event pendleRoutreUpdated(address _pendleRouterV4);

    /* ============ Errors ============ */

    error MarketAddressCanNotBeZero();
    error TokenAmountCanNotBeZero();
    error MinTokenOutCanNotBeZero();

    constructor() {
        _disableInitializers();
    }

    function __zapInAndOutHelper_init(
        address _pendleMarketDepositHelper,
        address _pendleStaking
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        pendleMarketDepositHelper = IPendleMarketDepositHelper(_pendleMarketDepositHelper);
        pendleStaking = IPendleStaking(_pendleStaking);
    }

    /* ============ External Functions ============ */

    function zapAndStake(
        tokenZapInData memory _tokenZapInData,
        bytes memory _kyberExecCallData,
        IPendleRouterV4.ApproxParams memory _pdexparams,
        IPendleRouterV4.SwapType _swapType
    ) external whenNotPaused nonReentrant {
        if (_tokenZapInData.market == address(0)) revert MarketAddressCanNotBeZero();
        if (_tokenZapInData.tokenAmount == 0) revert TokenAmountCanNotBeZero();
        if (_tokenZapInData.minTokenOut == 0) revert MinTokenOutCanNotBeZero();

        IERC20(_tokenZapInData.tokenInToZap).safeTransferFrom(msg.sender, address(this), _tokenZapInData.tokenAmount);
        IERC20(_tokenZapInData.tokenInToZap).safeApprove(address(pendleRouterV4), _tokenZapInData.tokenAmount);

        (uint256 _netLpOut) = _ZapInToPendleMarket(
            _tokenZapInData,
            _kyberExecCallData,
            _pdexparams,
            _swapType
        );

        emit zapInToPendleMarket( msg.sender, _tokenZapInData.tokenAmount, _tokenZapInData.market, _netLpOut );
    }

    function zapOutAndUnStake(
        tokenZapOutData memory _tokenZapOutData,
        bytes memory _kyberExecCallData,
        IPendleRouterV4.SwapType _swapType
    ) external whenNotPaused nonReentrant {
        if (_tokenZapOutData.market == address(0)) revert MarketAddressCanNotBeZero();
        if (_tokenZapOutData.tokenAmount == 0) revert TokenAmountCanNotBeZero();
        if (_tokenZapOutData.minTokenOut == 0) revert MinTokenOutCanNotBeZero();

        (uint256 tokenOutAmount) =  _ZapOutFromPendleMarket(
            _tokenZapOutData,
            _kyberExecCallData,
            _swapType
        );

        emit zapOutFromPendleMarket( msg.sender, _tokenZapOutData.tokenAmount, _tokenZapOutData.market, _tokenZapOutData.tokenForZapOut, tokenOutAmount );
    }

    /* ============ Internal Functions ============ */

    function _ZapInToPendleMarket(
        tokenZapInData memory _tokenZapInData,
        bytes memory execCallData,
        IPendleRouterV4.ApproxParams memory _pdexparams,
        IPendleRouterV4.SwapType _swapType
    ) internal returns(uint256 netLpOut) {
        IPendleRouterV4.FillOrderParams[] memory fillOrderParams = new IPendleRouterV4.FillOrderParams[](0);

        (netLpOut,, ) = pendleRouterV4.addLiquiditySingleToken(
            address(this),
            _tokenZapInData.market,
            _tokenZapInData.minTokenOut,
            _pdexparams,
            IPendleRouterV4.TokenInput(
                _tokenZapInData.tokenInToZap,
                _tokenZapInData.tokenAmount,
                _tokenZapInData.baseToken,
                pendleSwap,
                IPendleRouterV4.SwapData(
                    _swapType, 
                    kyberSwapRouter,
                    execCallData,
                    _tokenZapInData.needScale
                )
            ),
            IPendleRouterV4.LimitOrderData(
                ADDREESS_ZERO,
                0,
                fillOrderParams,
                fillOrderParams,
                "0x"
            )
        );

        IERC20(_tokenZapInData.market).safeApprove(address(pendleStaking), netLpOut);
        pendleMarketDepositHelper.depositMarketFor(_tokenZapInData.market, msg.sender, netLpOut);
    }

    function _ZapOutFromPendleMarket(
        tokenZapOutData memory _tokenZapOutData,
        bytes memory execCallData,
        IPendleRouterV4.SwapType _swapType
    ) internal returns (uint256 netTokenOut ){

        IERC20(IPendleStakingReader(address(pendleStaking)).pools(_tokenZapOutData.market).receiptToken).safeTransferFrom(msg.sender, address(this), _tokenZapOutData.tokenAmount);
        pendleMarketDepositHelper.withdrawMarket(_tokenZapOutData.market, _tokenZapOutData.tokenAmount);

        IERC20(_tokenZapOutData.market).safeApprove(address(pendleRouterV4), _tokenZapOutData.tokenAmount);

        IPendleRouterV4.FillOrderParams[] memory fillOrderParams = new IPendleRouterV4.FillOrderParams[](0);

        ( netTokenOut,, ) = pendleRouterV4.removeLiquiditySingleToken(
            msg.sender,
            _tokenZapOutData.market,
            _tokenZapOutData.tokenAmount,
            IPendleRouterV4.TokenOutput(
                _tokenZapOutData.tokenForZapOut,
                _tokenZapOutData.minTokenOut,
                _tokenZapOutData.baseToken,
                pendleSwap,
                IPendleRouterV4.SwapData(
                    _swapType, 
                    kyberSwapRouter,
                    execCallData,
                    _tokenZapOutData.needScale
                )
            ),
            IPendleRouterV4.LimitOrderData(
                ADDREESS_ZERO,
                0,
                fillOrderParams,
                fillOrderParams,
                "0x"
            )
        );
    }

    /* ============ Admin Functions ============ */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setKyberSwapRouter(address _kyberSwapRouter) external onlyOwner {
        kyberSwapRouter = _kyberSwapRouter;
        emit kyberSwapRouterUpdated(_kyberSwapRouter);
    }

    function setPendleSwap(address _pendleSwap) external onlyOwner {
        pendleSwap = _pendleSwap;
        emit pendleSwapUpdated(_pendleSwap);
    }

    function setPendleRouter(address _pendleRouterV4) external onlyOwner {
        pendleRouterV4 = IPendleRouterV4(_pendleRouterV4);
        emit pendleRoutreUpdated(_pendleRouterV4);
    }
}
