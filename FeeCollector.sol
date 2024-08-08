// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { UUPSUpgradeable } from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import { Initializable } from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import { OwnableUpgradeable } from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';

import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import './interfaces/IFeeCollector.sol';
import './libraries/UniversalERC20.sol';
import './helpers/PercentageManager.sol';

contract FeeCollector is
	OwnableUpgradeable,
	IFeeCollector,
	PercentageManager,
	UUPSUpgradeable
{
	using ECDSA for bytes32;
	using UniversalERC20 for IERC20;
	using MessageHashUtils for bytes32;

	address public olympexTreasury;
	address public olympiansTreasury;
	uint256 public percentageOlympex;
	uint256 public percentageOlympians;
	uint256 public platformFee;

	event FeesDistributed(IERC20 indexed token, address beneficiary);

	/// @dev Wallet address authorized to sign backend transactions for onchain validation.
	address internal _signerAddress;

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	receive() external payable virtual {}

	function __FeeCollector_init(
		address olympexTreasury_,
		address olympiansTreasury_,
		address signerAddress_,
		uint256 percentageOlympex_,
		uint256 percentageOlympians_
	) public initializer {
		__Ownable_init(msg.sender);
		__UUPSUpgradeable_init();
		olympexTreasury = olympexTreasury_;
		olympiansTreasury = olympiansTreasury_;
		_signerAddress = signerAddress_;

		require(
			percentageOlympex_ + percentageOlympians_ == PERCENTAGE_DENOMINATOR,
			'Invalid percentage'
		);

		platformFee = 30; // 0.3%;
		percentageOlympex = percentageOlympex_;
		percentageOlympians = percentageOlympians_;
	}

	function distributeFees(
		IERC20 token_,
		address receiver_,
		uint256 discountRate_,
		bytes calldata signature_
	) external validPercentage(discountRate_) {
		uint256 balance = token_.universalBalanceOf(address(this));
		require(balance > 0, 'Balance should not be 0');

		require(
			verifySignerDiscount(receiver_, discountRate_, signature_),
			'Invalid discount signature'
		);

		uint256 fee = platformFee > 0 ? (balance * platformFee) / PERCENTAGE_DENOMINATOR : 0;

		if (discountRate_ > 0 && fee > 0) {
			fee -= (fee * discountRate_) / PERCENTAGE_DENOMINATOR;
		}

		// If `msg.sender` is not the same contract then we send the rest of the funds
		// to the `receiver_`
		if (msg.sender != address(this)) {
			token_.universalTransfer(payable(receiver_), balance - fee);
		}

		if (fee > 0) {
			uint256 feeOlympex = (fee * percentageOlympex) / PERCENTAGE_DENOMINATOR;
			uint256 feeOlympians = (fee * percentageOlympians) / PERCENTAGE_DENOMINATOR;

			if (feeOlympex > 0) {
				token_.universalTransfer(payable(olympexTreasury), feeOlympex);
				emit FeesDistributed(token_, olympexTreasury);
			}

			if (feeOlympians > 0) {
				token_.universalTransfer(payable(olympiansTreasury), feeOlympians);
				emit FeesDistributed(token_, olympiansTreasury);
			}
		}
	}

	function setOlympiansTreasury(address olympiansTreasury_) external onlyOwner {
		olympiansTreasury = olympiansTreasury_;
	}

	function setOlympexTreasury(address olympexTreasury_) external onlyOwner {
		olympexTreasury = olympexTreasury_;
	}

	function setPlatformFee(
		uint256 platformFee_
	) external onlyOwner validPercentage(platformFee_) {
		platformFee = platformFee_;
	}

	function setFeePercentage(
		uint256 olympexFee_,
		uint256 olympiansFee_
	) external onlyOwner {
		require(olympexFee_ + olympiansFee_ == PERCENTAGE_DENOMINATOR, 'Invalid percentage');

		percentageOlympex = olympexFee_;
		percentageOlympians = olympiansFee_;
	}

	function verifySignerDiscount(
		address receiver_,
		uint256 discountRate_,
		bytes calldata signature_
	) internal view returns (bool) {
		return
			keccak256(abi.encodePacked(receiver_, discountRate_))
				.toEthSignedMessageHash()
				.recover(signature_) == _signerAddress;
	}

	function _authorizeUpgrade(
		address newImplementation
	) internal virtual override onlyOwner {}
}
