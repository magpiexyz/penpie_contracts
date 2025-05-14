// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../libraries/MarketApproxLib.sol";
import "../libraries/ActionBaseMintRedeem.sol";

interface IPendleStaking {

    function WETH() external view returns (address);

    function convertPendle(uint256 amount, uint256[] calldata chainid) external payable returns (uint256);

    function registerPool(address _market, uint256 _allocPoints, string memory name, string memory symbol) external;

    function vote(address[] calldata _pools, uint64[] calldata _weights) external;

    function depositMarket(address _market, address _for, address _from, uint256 _amount) external;

    function withdrawMarket(address _market,  address _for, uint256 _amount) external;

    function emergencyWithdraw(address _market,  address _for, uint256 _amount) external;

    function harvestMarketReward(address _lpAddress, address _callerAddress, uint256 _minEthRecive) external;
}
