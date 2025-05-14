// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISmartPendleConvert {
    
    function maxSwapAmount() external view returns (uint256);

    function estimateTotalConversion(uint256 _amount,uint256 _convertRatio) external view returns (uint256 minimumEstimatedTotal);

    function smartConvert(
        uint256 _amountIn,
        uint256 _mode
    ) external returns (uint256 obtainedMPendleAmount) ;

    function router() external view returns (address);

    function masterPenpie() external view returns (address);

    function pendleMPendlePool() external view returns (address);
    
    function currentRatio() external view returns (uint256);

    function buybackThreshold() external view returns (uint256);

}
