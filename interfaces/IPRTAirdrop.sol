// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPRTAirdrop {
    function getClaimed(address account) external view returns (uint256);

}
