// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import "@layerzerolabs/solidity-examples/contracts/token/oft/v2/OFTV2.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract Penpie is OFTV2, Pausable {

	/* ============ State Variables ============ */
	
	address public minter;

	/* ============ Constructor ============ */

    constructor(
		address _endpoint
	) OFTV2("Penpie Token", "PNP", 8, _endpoint) {
	}

	/* ============ External Functions ============ */	

	/* ============ Internal Functions ============ */

	function _debitFrom(
		address _from,
		uint16 _dstChainId,
		bytes32 _toAddress,
		uint _amount
	) internal override whenNotPaused returns (uint) {
		return super._debitFrom(_from, _dstChainId, _toAddress, _amount);
	}

	function _creditTo(uint16 _srcChainId, address _toAddress, uint _amount) internal override whenNotPaused returns (uint) {
		return super._creditTo(_srcChainId, _toAddress, _amount);
	}

	/* ============ Admin Functions ============ */

	function pause() public onlyOwner {
		_pause();
	}

	function unpause() public onlyOwner {
		_unpause();
	}
}