// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import './FeeCollector.sol';
import './messengers/DMMMessenger.sol';
import './messengers/SolidlyMessenger.sol';
import './messengers/UniswapMessenger.sol';
import './interfaces/IOlympexMessenger.sol';
import './messengers/SafeERC20Extension.sol';
import './libraries/MessageDescriptions.sol';
import './messengers/DistributionMessenger.sol';

contract OlympexMessenger is
	IOlympexMessenger,
	DistributionMessenger,
	SafeERC20Extension,
	UniswapV2LikeMessenger,
	UniswapV3Messenger,
	DMMMessenger,
	SolidlyMessenger,
	FeeCollector
{
	using MessageDescriptions for MessageDescription;

	constructor(
		address olympex_,
		address olympians_,
		address signerAddress_,
		uint256 percentageOlympex_,
		uint256 percentageOlympians_
	)
		FeeCollector(
			olympex_,
			olympians_,
			signerAddress_,
			percentageOlympex_,
			percentageOlympians_
		)
	{}

	receive() external payable {
		// cannot directly send eth to this contract
		// TODO: hay que evaluar si realmente es necesario colocar esta restricción
		// require(msg.sender != tx.origin);
	}

	function makeCall(MessageDescription memory desc) external override {
		(bool success, string memory errorMessage) = desc.execute();
		if (!success) {
			revert(errorMessage);
		}
	}

	function makeCalls(MessageDescription[] memory desc) external payable override {
		require(desc.length > 0, 'Olympex: Invalid call parameter');
		for (uint256 i = 0; i < desc.length; i++) {
			this.makeCall(desc[i]);
		}
	}
}
