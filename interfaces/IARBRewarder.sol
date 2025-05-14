// SPDX-License-Identifier: MIT

pragma solidity =0.8.19;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IARBRewarder {

    function harvestARB(address _stakingToken, address _user) external;

    function ARB() external view returns(IERC20 ARB);

    function massUpdatePools() external;
    
}