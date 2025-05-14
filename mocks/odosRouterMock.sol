// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockOdosRouter {

    mapping(address => mapping(address => uint256)) public swapMap;
    uint256 public constant DENOMINATOR = 10000;

    function setTokens(
        address _from,
        address _to,
        uint256 _ratio
    ) external {
        swapMap[_from][_to] = _ratio;
    }

    function compactSwap(address tokenIn, address tokenOut, uint256 amountIn, address to) external {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        uint256 amountOut = (swapMap[tokenIn][tokenOut] * amountIn) / DENOMINATOR;

        // IERC20(tokenOut).approve(to, amountOut);
        IERC20(tokenOut).transfer(to, amountOut);
    }
}
