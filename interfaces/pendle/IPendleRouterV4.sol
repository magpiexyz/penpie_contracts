// SPDX-License-Identifier:MIT
pragma solidity =0.8.19;

interface IPendleRouterV4 {
    struct SwapData {
        SwapType swapType;
        address extRouter;
        bytes extCalldata;
        bool needScale;
    }

    enum SwapType {
        NONE,
        KYBERSWAP,
        ONE_INCH,
        // ETH_WETH not used in Aggregator
        ETH_WETH
    }

    struct ApproxParams {
        uint256 guessMin;
        uint256 guessMax;
        uint256 guessOffchain;
        uint256 maxIteration;
        uint256 eps;
    }

    struct TokenInput {
        // TOKEN DATA
        address tokenIn;
        uint256 netTokenIn;
        address tokenMintSy;
        // AGGREGATOR DATA
        address pendleSwap;
        SwapData swapData;
    }

    struct TokenOutput {
        // TOKEN DATA
        address tokenOut;
        uint256 minTokenOut;
        address tokenRedeemSy;
        // AGGREGATOR DATA
        address pendleSwap;
        SwapData swapData;
    }

    function redeemDueInterestAndRewards(
        address user,
        address[] calldata sys,
        address[] calldata yts,
        address[] calldata markets
    ) external;

    enum OrderType {
        SY_FOR_PT,
        PT_FOR_SY,
        SY_FOR_YT,
        YT_FOR_SY
    }

    struct Order {
        uint256 salt;
        uint256 expiry;
        uint256 nonce;
        OrderType orderType;
        address token;
        address YT;
        address maker;
        address receiver;
        uint256 makingAmount;
        uint256 lnImpliedRate;
        uint256 failSafeRate;
        bytes permit;
    }

    struct FillOrderParams {
        Order order;
        bytes signature;
        uint256 makingAmount;
    }
    struct LimitOrderData {
        address limitRouter;
        uint256 epsSkipMarket; // only used for swap operations, will be ignored otherwise
        FillOrderParams[] normalFills;
        FillOrderParams[] flashFills;
        bytes optData;
    }

    function addLiquiditySingleToken(
        address receiver,
        address market,
        uint256 minLpOut,
        ApproxParams calldata guessPtReceivedFromSy,
        TokenInput calldata input,
        LimitOrderData calldata limit
    ) external payable returns (uint256 netLpOut, uint256 netSyFee, uint256 netSyInterm);

    function removeLiquiditySingleToken(
        address receiver,
        address market,
        uint256 netLpToRemove,
        TokenOutput calldata output,
        LimitOrderData calldata limit
    ) external returns (uint256 netTokenOut, uint256 netSyFee, uint256 netSyInterm);
}
