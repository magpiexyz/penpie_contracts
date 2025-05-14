pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/pancakeswap/IStableSwapRouter.sol";
import "../../interfaces/pancakeswap/IPancakeStableSwapTwoPool.sol";

contract StableSwapRouterMock is IStableSwapRouter, IPancakeStableSwapTwoPool {
    mapping(address => mapping(address => uint256)) public swapMap;
    mapping(uint256 => address) public tokenMap;
    mapping(address => uint256) public tokenBalances;
    uint256 public constant denominator = 10000;
    uint256 public constant CONTRACT_BALANCE = 0;

    constructor() {}

    function setTokens(
        address _from,
        address _to,
        uint256 _ratio,
        uint256 _fromBalance,
        uint256 _toBalance
    ) external {
        swapMap[_from][_to] = _ratio;
        tokenMap[0] = _from;
        tokenMap[1] = _to;
        tokenBalances[_from] = _fromBalance;
        tokenBalances[_to] = _toBalance;
    }

    function get_dy(
        uint256 token0,
        uint256 token1,
        uint256 inputAmount
    ) external view returns (uint256 outputAmount) {
        address fromToken = tokenMap[token0];
        address toToken = tokenMap[token1];

        outputAmount = (swapMap[fromToken][toToken] * inputAmount) / denominator;
    }

    function exactInputStableSwap(
        address[] calldata path,
        uint256[] calldata flag,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) external payable returns (uint256 amountOut) {
        IERC20 srcToken = IERC20(path[0]);

        // use amountIn == CONTRACT_BALANCE as a flag to swap the entire balance of the contract
        bool hasAlreadyPaid;
        if (amountIn == CONTRACT_BALANCE) {
            hasAlreadyPaid = true;
            amountIn = srcToken.balanceOf(address(this));
        }
        if (!hasAlreadyPaid) {
            srcToken.transferFrom(msg.sender, address(this), amountIn);
        }

        _swap(path, flag, to, amountOutMin);
    }

    function _swap(
        address[] memory path,
        uint256[] memory flag,
        address to,
        uint256 amountOutMin
    ) private {
        for (uint256 i; i < flag.length; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            uint256 amountIn_ = IERC20(input).balanceOf(address(this));
            uint256 amountOut = (swapMap[input][output] * amountIn_) / denominator;
            require(amountOut >= amountOutMin, "MinRecNotMatch()");
            IERC20(output).transfer(to, amountOut);
        }
    }

    function balances(uint256 index) external view override returns (uint256) {
        return tokenBalances[tokenMap[index]];
    }
}
