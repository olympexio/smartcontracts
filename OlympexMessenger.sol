// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { UUPSUpgradeable } from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import './FeeCollector.sol';

import './messengers/DMMMessenger.sol';
import './messengers/SolidlyMessenger.sol';
import './messengers/UniswapMessenger.sol';
import './interfaces/IOlympexMessenger.sol';
import './messengers/SafeERC20Extension.sol';
import './libraries/MessageDescriptions.sol';
import './messengers/DistributionMessenger.sol';

contract OlympexMessenger is
	UUPSUpgradeable,
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

	/// @dev storage gaps for contract upgrade
	uint256[50] __gap;

	function initialize(
		address olympex_,
		address olympians_,
		address signerAddress_,
		uint256 percentageOlympex_,
		uint256 percentageOlympians_,
		address uniswapV3Factory_
	) public initializer {
		__Ownable_init(msg.sender);
		__UUPSUpgradeable_init();
		FeeCollector.__FeeCollector_init(
			olympex_,
			olympians_,
			signerAddress_,
			percentageOlympex_,
			percentageOlympians_
		);
		setUniswapV3FactoryAddress(uniswapV3Factory_);
	}

	receive() external payable override {
		// cannot directly send eth to this contract
		require(msg.sender != tx.origin);
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

	function setUniswapV3FactoryAddress(address uniswapV3Factory_) public onlyOwner {
		uniswapV3Factory = uniswapV3Factory_;
	}

	function _authorizeUpgrade(
		address newImplementation
	) internal override(UUPSUpgradeable, FeeCollector) onlyOwner {}
}
