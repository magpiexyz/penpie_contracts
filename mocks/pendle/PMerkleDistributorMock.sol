// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../../interfaces/pendle/IPMerkleDistributor.sol";


contract PMerkleDistributorMock is
    IPMerkleDistributor,
    OwnableUpgradeable
{
    address public immutable token;

    bytes32 public merkleRoot;

    mapping(address => uint256) public claimed;
    mapping(address => uint256) public verified;

    constructor(address _token) {
        token = _token;
    }

    receive() external payable {}

    function claim(
        address receiver,
        uint256 totalAccrued,
        bytes32[] calldata proof
    ) external returns (uint256 amountOut) {

        amountOut = totalAccrued - claimed[msg.sender];
        IERC20(token).transfer(receiver, amountOut);
        claimed[msg.sender] = totalAccrued;
    }

    function claimVerified(address receiver) external returns (uint256 amountOut) {
        address user = msg.sender;
        uint256 amountVerified = verified[user];
        uint256 amountClaimed = claimed[user];

        if (amountVerified <= amountClaimed) {
            return 0;
        }

        amountOut = amountVerified - amountClaimed;
        claimed[user] = amountVerified;

        IERC20(token).transfer(receiver, amountOut);
        emit Claimed(user, receiver, amountOut);
    }

    function verify(
        address user,
        uint256 totalAccrued,
        bytes32[] calldata proof
    ) external returns (uint256 amountClaimable) {
       
        amountClaimable = totalAccrued - claimed[user];
        verified[user] = totalAccrued;

        emit Verified(user, amountClaimable);
    }
}