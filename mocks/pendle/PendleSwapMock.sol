// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../libraries/TokenHelper.sol";
import "../../interfaces/pendle/IPSwapAggregator.sol";


// pragma solidity >=0.6.12;

interface IAggregationExecutor {
    function callBytes(bytes calldata data) external payable; // 0xd9c45357

    // callbytes per swap sequence
    function swapSingleSequence(bytes calldata data) external;

    function finalTransactionProcessing(
        address tokenIn,
        address tokenOut,
        address to,
        bytes calldata destTokenFeeData
    ) external;
}

// pragma solidity 0.8.19;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMetaAggregationRouterV2 {
    struct SwapDescriptionV2 {
        IERC20 srcToken;
        IERC20 dstToken;
        address[] srcReceivers; // transfer src token to these addresses, default
        uint256[] srcAmounts;
        address[] feeReceivers;
        uint256[] feeAmounts;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
        bytes permit;
    }

    /// @dev  use for swapGeneric and swap to avoid stack too deep
    struct SwapExecutionParams {
        address callTarget; // call this address
        address approveTarget; // approve this address if _APPROVE_FUND set
        bytes targetData;
        SwapDescriptionV2 desc;
        bytes clientData;
    }

    function swap(SwapExecutionParams calldata execution)
        external
        payable
        returns (uint256, uint256);

    function swapSimpleMode(
        IAggregationExecutor caller,
        SwapDescriptionV2 memory desc,
        bytes calldata executorData,
        bytes calldata clientData
    ) external returns (uint256, uint256);
}


// pragma solidity 0.8.19;

interface IHashflow {
    enum RFQType {
        TAKER,
        MAKER
    }

    struct Quote {
        RFQType rfqType;
        address pool;
        address eoa;
        address trader;
        address effectiveTrader;
        address baseToken;
        address quoteToken;
        uint256 effectiveBaseTokenAmount;
        uint256 maxBaseTokenAmount;
        uint256 maxQuoteTokenAmount;
        uint256 fees;
        uint256 quoteExpiry;
        uint256 nonce;
        bytes32 txid;
        bytes signedQuote;
    }

    function tradeSingleHop(Quote memory quote) external payable;
}
// pragma solidity 0.8.19;

interface IExecutorHelper {
    struct Swap {
        bytes data;
        bytes4 functionSelector;
    }

    struct SwapExecutorDescription {
        Swap[][] swapSequences;
        address tokenIn;
        address tokenOut;
        uint256 minTotalAmountOut;
        address to;
        uint256 deadline;
        bytes destTokenFeeData;
    }

    struct UniSwap {
        address pool;
        address tokenIn;
        address tokenOut;
        address recipient;
        uint256 collectAmount; // amount that should be transferred to the pool
        uint256 limitReturnAmount;
        uint32 swapFee;
        uint32 feePrecision;
        uint32 tokenWeightInput;
    }

    struct StableSwap {
        address pool;
        address tokenFrom;
        address tokenTo;
        uint8 tokenIndexFrom;
        uint8 tokenIndexTo;
        uint256 dx;
        uint256 minDy;
        uint256 poolLength;
        address poolLp;
        bool isSaddle; // true: saddle, false: stable
    }

    struct CurveSwap {
        address pool;
        address tokenFrom;
        address tokenTo;
        int128 tokenIndexFrom;
        int128 tokenIndexTo;
        uint256 dx;
        uint256 minDy;
        bool usePoolUnderlying;
        bool useTriCrypto;
    }

    struct UniSwapV3ProMM {
        address recipient;
        address pool;
        address tokenIn;
        address tokenOut;
        uint256 swapAmount;
        uint256 limitReturnAmount;
        uint160 sqrtPriceLimitX96;
        bool isUniV3; // true = UniV3, false = ProMM
    }

    struct BalancerV2 {
        address vault;
        bytes32 poolId;
        address assetIn;
        address assetOut;
        uint256 amount;
        uint256 limit;
    }

    struct DODO {
        address recipient;
        address pool;
        address tokenFrom;
        address tokenTo;
        uint256 amount;
        uint256 minReceiveQuote;
        address sellHelper;
        bool isSellBase;
        bool isVersion2;
    }

    struct GMX {
        address vault;
        address tokenIn;
        address tokenOut;
        uint256 amount;
        uint256 minOut;
        address receiver;
    }

    struct Synthetix {
        address synthetixProxy;
        address tokenIn;
        address tokenOut;
        bytes32 sourceCurrencyKey;
        uint256 sourceAmount;
        bytes32 destinationCurrencyKey;
        uint256 minAmount;
        bool useAtomicExchange;
    }

    struct Platypus {
        address pool;
        address tokenIn;
        address tokenOut;
        address recipient;
        uint256 collectAmount; // amount that should be transferred to the pool
        uint256 limitReturnAmount;
    }

    struct PSM {
        address router;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        address recipient;
    }

    struct WSTETH {
        address pool;
        uint256 amount;
        bool isWrapping;
    }

    function executeUniSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeStableSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeCurveSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeKyberDMMSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeUniV3ProMMSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeRfqSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeBalV2Swap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeDODOSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeVelodromeSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeGMXSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executePlatypusSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeWrappedstETHSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeSynthetixSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeHashflowSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executePSMSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeFraxSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeCamelotSwap(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);

    function executeKyberLimitOrder(
        uint256 index,
        bytes memory data,
        uint256 previousAmountOut
    ) external payable returns (uint256);
}
// pragma solidity 0.8.19;

library ScalingDataLib {
    function newUniSwap(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.UniSwap memory uniSwap = abi.decode(data, (IExecutorHelper.UniSwap));
        uniSwap.collectAmount = (uniSwap.collectAmount * newAmount) / oldAmount;
        return abi.encode(uniSwap);
    }

    function newStableSwap(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.StableSwap memory stableSwap = abi.decode(
            data,
            (IExecutorHelper.StableSwap)
        );
        stableSwap.dx = (stableSwap.dx * newAmount) / oldAmount;
        return abi.encode(stableSwap);
    }

    function newCurveSwap(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.CurveSwap memory curveSwap = abi.decode(data, (IExecutorHelper.CurveSwap));
        curveSwap.dx = (curveSwap.dx * newAmount) / oldAmount;
        return abi.encode(curveSwap);
    }

    function newKyberDMM(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.UniSwap memory kyberDMMSwap = abi.decode(data, (IExecutorHelper.UniSwap));
        kyberDMMSwap.collectAmount = (kyberDMMSwap.collectAmount * newAmount) / oldAmount;
        return abi.encode(kyberDMMSwap);
    }

    function newUniV3ProMM(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.UniSwapV3ProMM memory uniSwapV3ProMM = abi.decode(
            data,
            (IExecutorHelper.UniSwapV3ProMM)
        );
        uniSwapV3ProMM.swapAmount = (uniSwapV3ProMM.swapAmount * newAmount) / oldAmount;

        return abi.encode(uniSwapV3ProMM);
    }

    function newBalancerV2(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.BalancerV2 memory balancerV2 = abi.decode(
            data,
            (IExecutorHelper.BalancerV2)
        );
        balancerV2.amount = (balancerV2.amount * newAmount) / oldAmount;
        return abi.encode(balancerV2);
    }

    function newDODO(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.DODO memory dodo = abi.decode(data, (IExecutorHelper.DODO));
        dodo.amount = (dodo.amount * newAmount) / oldAmount;
        return abi.encode(dodo);
    }

    function newVelodrome(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.UniSwap memory velodrome = abi.decode(data, (IExecutorHelper.UniSwap));
        velodrome.collectAmount = (velodrome.collectAmount * newAmount) / oldAmount;
        return abi.encode(velodrome);
    }

    function newGMX(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.GMX memory gmx = abi.decode(data, (IExecutorHelper.GMX));
        gmx.amount = (gmx.amount * newAmount) / oldAmount;
        return abi.encode(gmx);
    }

    function newSynthetix(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.Synthetix memory synthetix = abi.decode(data, (IExecutorHelper.Synthetix));
        synthetix.sourceAmount = (synthetix.sourceAmount * newAmount) / oldAmount;
        return abi.encode(synthetix);
    }

    function newCamelot(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.UniSwap memory camelot = abi.decode(data, (IExecutorHelper.UniSwap));
        camelot.collectAmount = (camelot.collectAmount * newAmount) / oldAmount;
        return abi.encode(camelot);
    }

    function newPlatypus(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.Platypus memory platypus = abi.decode(data, (IExecutorHelper.Platypus));
        platypus.collectAmount = (platypus.collectAmount * newAmount) / oldAmount;
        return abi.encode(platypus);
    }

    function newWrappedstETHSwap(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.WSTETH memory wstEthData = abi.decode(data, (IExecutorHelper.WSTETH));
        wstEthData.amount = (wstEthData.amount * newAmount) / oldAmount;
        return abi.encode(wstEthData);
    }

    function newPSM(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.PSM memory psm = abi.decode(data, (IExecutorHelper.PSM));
        psm.amountIn = (psm.amountIn * newAmount) / oldAmount;
        return abi.encode(psm);
    }

    function newFrax(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.UniSwap memory frax = abi.decode(data, (IExecutorHelper.UniSwap));
        frax.collectAmount = (frax.collectAmount * newAmount) / oldAmount;
        return abi.encode(frax);
    }
}


// pragma solidity 0.8.19;

abstract contract KyberInputScalingHelper {
    uint256 private constant _PARTIAL_FILL = 0x01;
    uint256 private constant _REQUIRES_EXTRA_ETH = 0x02;
    uint256 private constant _SHOULD_CLAIM = 0x04;
    uint256 private constant _BURN_FROM_MSG_SENDER = 0x08;
    uint256 private constant _BURN_FROM_TX_ORIGIN = 0x10;
    uint256 private constant _SIMPLE_SWAP = 0x20;

    // fee data in case taking in dest token
    struct PositiveSlippageFeeData {
        uint256 partnerPSInfor; // [partnerReceiver (160 bit) + partnerPercent(96bits)]
        uint256 expectedReturnAmount;
    }

    struct Swap {
        bytes data;
        bytes4 functionSelector;
    }

    struct SimpleSwapData {
        address[] firstPools;
        uint256[] firstSwapAmounts;
        bytes[] swapDatas;
        uint256 deadline;
        bytes positiveSlippageData;
    }

    struct SwapExecutorDescription {
        Swap[][] swapSequences;
        address tokenIn;
        address tokenOut;
        uint256 minTotalAmountOut;
        address to;
        uint256 deadline;
        bytes positiveSlippageData;
    }

    function _getKyberScaledInputData(bytes calldata inputData, uint256 newAmount)
        internal
        pure
        returns (bytes memory)
    {
        bytes4 selector = bytes4(inputData[:4]);
        bytes calldata dataToDecode = inputData[4:];

        if (selector == IMetaAggregationRouterV2.swap.selector) {
            IMetaAggregationRouterV2.SwapExecutionParams memory params = abi.decode(
                dataToDecode,
                (IMetaAggregationRouterV2.SwapExecutionParams)
            );

            (params.desc, params.targetData) = _getScaledInputDataV2(
                params.desc,
                params.targetData,
                newAmount,
                _flagsChecked(params.desc.flags, _SIMPLE_SWAP)
            );
            return abi.encodeWithSelector(selector, params);
        } else if (selector == IMetaAggregationRouterV2.swapSimpleMode.selector) {
            (
                address callTarget,
                IMetaAggregationRouterV2.SwapDescriptionV2 memory desc,
                bytes memory targetData,
                bytes memory clientData
            ) = abi.decode(
                    dataToDecode,
                    (address, IMetaAggregationRouterV2.SwapDescriptionV2, bytes, bytes)
                );

            (desc, targetData) = _getScaledInputDataV2(desc, targetData, newAmount, true);
            return abi.encodeWithSelector(selector, callTarget, desc, targetData, clientData);
        } else revert("InputScalingHelper: Invalid selector");
    }

    function _getScaledInputDataV2(
        IMetaAggregationRouterV2.SwapDescriptionV2 memory desc,
        bytes memory executorData,
        uint256 newAmount,
        bool isSimpleMode
    ) internal pure returns (IMetaAggregationRouterV2.SwapDescriptionV2 memory, bytes memory) {
        uint256 oldAmount = desc.amount;
        if (oldAmount == newAmount) {
            return (desc, executorData);
        }

        // simple mode swap
        if (isSimpleMode) {
            return (
                _scaledSwapDescriptionV2(desc, oldAmount, newAmount),
                _scaledSimpleSwapData(executorData, oldAmount, newAmount)
            );
        }

        //normal mode swap
        return (
            _scaledSwapDescriptionV2(desc, oldAmount, newAmount),
            _scaledExecutorCallBytesData(executorData, oldAmount, newAmount)
        );
    }

    /// @dev Scale the swap description
    function _scaledSwapDescriptionV2(
        IMetaAggregationRouterV2.SwapDescriptionV2 memory desc,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (IMetaAggregationRouterV2.SwapDescriptionV2 memory) {
        desc.minReturnAmount = (desc.minReturnAmount * newAmount) / oldAmount;
        if (desc.minReturnAmount == 0) desc.minReturnAmount = 1;
        desc.amount = newAmount;

        uint256 nReceivers = desc.srcReceivers.length;
        for (uint256 i = 0; i < nReceivers; ) {
            desc.srcAmounts[i] = (desc.srcAmounts[i] * newAmount) / oldAmount;
            unchecked {
                ++i;
            }
        }
        return desc;
    }

    /// @dev Scale the executorData in case swapSimpleMode
    function _scaledSimpleSwapData(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        SimpleSwapData memory swapData = abi.decode(data, (SimpleSwapData));

        uint256 nPools = swapData.firstPools.length;
        for (uint256 i = 0; i < nPools; ) {
            swapData.firstSwapAmounts[i] = (swapData.firstSwapAmounts[i] * newAmount) / oldAmount;
            unchecked {
                ++i;
            }
        }
        swapData.positiveSlippageData = _scaledPositiveSlippageFeeData(
            swapData.positiveSlippageData,
            oldAmount,
            newAmount
        );
        return abi.encode(swapData);
    }

    /// @dev Scale the executorData in case normal swap
    function _scaledExecutorCallBytesData(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        SwapExecutorDescription memory executorDesc = abi.decode(data, (SwapExecutorDescription));
        executorDesc.minTotalAmountOut = (executorDesc.minTotalAmountOut * newAmount) / oldAmount;
        executorDesc.positiveSlippageData = _scaledPositiveSlippageFeeData(
            executorDesc.positiveSlippageData,
            oldAmount,
            newAmount
        );

        uint256 nSequences = executorDesc.swapSequences.length;
        for (uint256 i = 0; i < nSequences; ) {
            Swap memory swap = executorDesc.swapSequences[i][0];
            bytes4 functionSelector = swap.functionSelector;

            if (functionSelector == IExecutorHelper.executeUniSwap.selector) {
                swap.data = ScalingDataLib.newUniSwap(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeStableSwap.selector) {
                swap.data = ScalingDataLib.newStableSwap(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeCurveSwap.selector) {
                swap.data = ScalingDataLib.newCurveSwap(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeKyberDMMSwap.selector) {
                swap.data = ScalingDataLib.newKyberDMM(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeUniV3ProMMSwap.selector) {
                swap.data = ScalingDataLib.newUniV3ProMM(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeRfqSwap.selector) {
                revert("InputScalingHelper: Can not scale RFQ swap");
            } else if (functionSelector == IExecutorHelper.executeBalV2Swap.selector) {
                swap.data = ScalingDataLib.newBalancerV2(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeWrappedstETHSwap.selector) {
                swap.data = ScalingDataLib.newWrappedstETHSwap(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeDODOSwap.selector) {
                swap.data = ScalingDataLib.newDODO(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeVelodromeSwap.selector) {
                swap.data = ScalingDataLib.newVelodrome(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeGMXSwap.selector) {
                swap.data = ScalingDataLib.newGMX(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeSynthetixSwap.selector) {
                swap.data = ScalingDataLib.newSynthetix(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeHashflowSwap.selector) {
                revert("InputScalingHelper: Can not scale RFQ swap");
            } else if (functionSelector == IExecutorHelper.executeCamelotSwap.selector) {
                swap.data = ScalingDataLib.newCamelot(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeKyberLimitOrder.selector) {
                revert("InputScalingHelper: Can not scale RFQ swap");
            } else if (functionSelector == IExecutorHelper.executePSMSwap.selector) {
                swap.data = ScalingDataLib.newPSM(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeFraxSwap.selector) {
                swap.data = ScalingDataLib.newFrax(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executePlatypusSwap.selector) {
                swap.data = ScalingDataLib.newPlatypus(swap.data, oldAmount, newAmount);
            } else revert("AggregationExecutor: Dex type not supported");
            unchecked {
                ++i;
            }
        }
        return abi.encode(executorDesc);
    }

    function _scaledPositiveSlippageFeeData(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory newData) {
        if (data.length > 32) {
            PositiveSlippageFeeData memory psData = abi.decode(data, (PositiveSlippageFeeData));
            psData.expectedReturnAmount = (psData.expectedReturnAmount * newAmount) / oldAmount;
            data = abi.encode(psData);
        } else if (data.length == 32) {
            uint256 expectedReturnAmount = abi.decode(data, (uint256));
            expectedReturnAmount = (expectedReturnAmount * newAmount) / oldAmount;
            data = abi.encode(expectedReturnAmount);
        }
        return data;
    }

    function _flagsChecked(uint256 number, uint256 flag) internal pure returns (bool) {
        return number & flag != 0;
    }
}

contract PendleSwapMock is IPSwapAggregator, TokenHelper, KyberInputScalingHelper {
    using Address for address;

    function swap(
        address tokenIn,
        uint256 amountIn,
        SwapData calldata data
    ) external payable {
        _safeApproveInf(tokenIn, data.extRouter);
        data.extRouter.functionCallWithValue(
            data.needScale
                ? _getScaledInputData(data.swapType, data.extCalldata, amountIn)
                : data.extCalldata,
            tokenIn == NATIVE ? amountIn : 0
        );
    }

    function _getScaledInputData(
        SwapType swapType,
        bytes calldata rawCallData,
        uint256 amountIn
    ) internal pure returns (bytes memory scaledCallData) {
        if (swapType == SwapType.KYBERSWAP) {
            scaledCallData = _getKyberScaledInputData(rawCallData, amountIn);
        } else if (swapType == SwapType.ONE_INCH) {
            revert("not supported");
        } else {
            assert(false);
        }
    }

    receive() external payable {}
}
