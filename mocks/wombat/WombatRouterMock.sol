pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import "../../interfaces/wombat/IWombatRouter.sol";

contract WombatRouterMock is IWombatRouter {

    mapping(address => mapping(address => uint256)) public swapMap;
    uint256 public constant denominator = 10000;
    uint256 public nextSpecifiedAmountOut;

    constructor() {}

    function setRatio(address _from, address _to, uint256 _ratio) external {
        swapMap[_from][_to] = _ratio;
    }

    function getAmountOut(
        address[] calldata tokenPath,
        address[] calldata poolPath,
        int256 amountIn
    ) external override view returns (uint256 amountOut, uint256[] memory haircuts) {
        address fromToken = tokenPath[0];
        address toToken = tokenPath[1];

        amountOut = swapMap[fromToken][toToken] * uint256(amountIn) / denominator;
    }

    function swapExactTokensForTokens(
        address[] calldata tokenPath,
        address[] calldata poolPath,
        uint256 amountIn,
        uint256 minimumamountOut,
        address to,
        uint256 deadline
    ) external override returns (uint256 amountOut) {
        address fromToken = tokenPath[0];
        address toToken = tokenPath[1];

        IERC20(fromToken).transferFrom(msg.sender, address(this), amountIn);

        if (nextSpecifiedAmountOut != 0) {
            IERC20(toToken).transfer(to, nextSpecifiedAmountOut);
            amountOut = nextSpecifiedAmountOut;
            nextSpecifiedAmountOut = 0;
        } else {
            amountOut = swapMap[fromToken][toToken] * uint256(amountIn) / denominator;
            IERC20(toToken).transfer(to, amountOut);
        }
    }

    function setNextOutput(uint256 _nextSpecifiedAmountOut) external {
        nextSpecifiedAmountOut = _nextSpecifiedAmountOut;
    }

}