// SPDX-License-Identifier: MIT

pragma solidity >=0.8.20 <=0.8.24;

import { OwnableUpgradeable } from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import { UUPSUpgradeable } from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import { Initializable } from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import { ECDSA } from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import { MessageHashUtils } from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { IFeeDistributor } from './interfaces/IFeeDistributor.sol';
import { UniversalERC20 } from './libraries/UniversalERC20.sol';
import { PercentageManager } from './helpers/PercentageManager.sol';
import { IPartnersTreasury } from './interfaces/IPartnersTreasury.sol';

contract FeeDistributor is
	IFeeDistributor,
	PercentageManager,
	OwnableUpgradeable,
	UUPSUpgradeable
{
	/********
	 * INDEX *
	 *********/
	// 1. Type declarations.
	// 2. Constants and variables.
	// 3. Events.
	// 4. Functions.

	/***********************
	 * 1. TYPE DECLARATIONS *
	 ************************/
	using ECDSA for bytes32;
	using UniversalERC20 for IERC20;
	using MessageHashUtils for bytes32;

	/*****************************
	 * 2. CONSTANTS AND VARIABLES *
	 ******************************/
	uint256 public platformFee;
	address public olympexTreasury;
	address public olympiansTreasury;
	uint256 public percentageOlympex;
	IPartnersTreasury public partnersTreasury;

	/// @dev storage gaps for contract upgrade
	uint256[50] __gap;

	/// @dev Wallet address authorized to sign backend transactions for onchain validation.
	address internal _signerAddress;

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	receive() external payable virtual {}

	function __FeeDistributor_init(
		address olympexTreasury_,
		address signerAddress_,
		uint256 percentageOlympex_
	) public initializer {
		__UUPSUpgradeable_init();
		__Ownable_init(msg.sender);

		if (olympexTreasury_ == address(0)) revert InvalidOlympexTreasury();
		if (signerAddress_ == address(0)) revert InvalidSignerAddress();
		if (percentageOlympex_ > PERCENTAGE_DENOMINATOR) revert InvalidPercentage();

		__FeeDistributor_init_unchained(olympexTreasury_, signerAddress_, percentageOlympex_);
	}

	function __FeeDistributor_init_unchained(
		address olympexTreasury_,
		address signerAddress_,
		uint256 percentageOlympex_
	) internal onlyInitializing {
		olympexTreasury = olympexTreasury_;
		_signerAddress = signerAddress_;

		platformFee = 3_000; // 0.3%;
		percentageOlympex = percentageOlympex_;
	}

	function setPartnersTreasury(IPartnersTreasury partnersTreasury_) external onlyOwner {
		if (address(partnersTreasury_) == address(0)) revert CannotBeZeroAddress();

		emit ChangePartnersTreasury(partnersTreasury = partnersTreasury_);
	}

	function setOlympiansTreasury(address olympiansTreasury_) external onlyOwner {
		if (olympiansTreasury_ == address(0)) revert CannotBeZeroAddress();

		emit SetOlympiansTreasury(olympiansTreasury = olympiansTreasury_);
	}

	function setOlympexTreasury(address olympexTreasury_) external onlyOwner {
		if (olympexTreasury_ == address(0)) revert InvalidOlympexTreasury();

		emit SetOlympexTreasury(olympexTreasury = olympexTreasury_);
	}

	function setPlatformFee(uint256 fee_) external onlyOwner validPercentage(fee_) {
		if (fee_ > PERCENTAGE_DENOMINATOR) revert InvalidPercentage();

		emit SetPlatformFee(platformFee = fee_);
	}

	function setFeePercentage(uint256 fee_) external onlyOwner validPercentage(fee_) {
		if (fee_ > PERCENTAGE_DENOMINATOR) revert InvalidPercentage();

		emit SetFeePercentage(percentageOlympex = fee_);
	}

	function setSignerAddress(address signerAddress_) external onlyOwner {
		if (signerAddress_ == address(0)) revert InvalidSignerAddress();

		emit SetSignerAddress(_signerAddress = signerAddress_);
	}

	function getSignerAddress() external view returns (address) {
		return _signerAddress;
	}

	/**
	 * @dev It is responsible for distributing the fees obtained from the balance sheet,
	 * that means everything that is in the contract balance sheet will be distributed
	 * @param token_ Token in which the fees were paid
	 * @param receiver_ address who receives the discount obtained and any leftover balance
	 * @param feeDescription_ Information related to the discount applied to the user
	 **/
	function distributeFees(
		IERC20 token_,
		address receiver_,
		FeeDescription calldata feeDescription_
	) external payable validPercentage(feeDescription_.discountRate) {
		uint256 discount;
		uint256 fees = token_.universalBalanceOf(address(this));

		if (fees <= 0) revert FeesShouldNotBe0();

		if (feeDescription_.discountRate > 0) {
			discount = (fees * feeDescription_.discountRate) / PERCENTAGE_DENOMINATOR;
		}

		// If applicable, we return to the receiver_ the discount obtained by your NFT
		if (discount > 0) {
			fees -= discount;
			token_.universalTransfer(payable(receiver_), discount);
			emit DiscountRefund(token_, receiver_, discount);
		}

		// Distribute the fees if there is still a balance after applying the discount
		if (fees > 0) {
			_distributeFees(fees, token_, feeDescription_);
		}
	}

	function _distributeFees(
		uint256 fees_,
		IERC20 token_,
		FeeDescription calldata feeDescription_
	) internal {
		uint256 _fees = fees_;

		if (feeDescription_.isReferredB2B) {
			uint256 parnerFees = (fees_ * feeDescription_.partnerPercentage) /
				PERCENTAGE_DENOMINATOR;

			_fees -= parnerFees;

			if (!token_.isETH()) {
				token_.universalApprove(address(partnersTreasury), parnerFees);
			}

			partnersTreasury.distributeFeesToPartner{ value: token_.isETH() ? parnerFees : 0 }(
				feeDescription_.partner,
				token_,
				parnerFees
			);
		}

		uint256 feeOlympex = (_fees * percentageOlympex) / PERCENTAGE_DENOMINATOR;
		uint256 feeOlympians = _fees - feeOlympex;

		token_.universalTransfer(payable(olympexTreasury), feeOlympex);
		emit FeesDistributed(token_, olympexTreasury, feeOlympex);

		token_.universalTransfer(payable(olympiansTreasury), feeOlympians);
		emit FeesDistributed(token_, olympiansTreasury, feeOlympians);
	}

	/**
	 * @notice Returns the percentage denominator used for percentage calculations
	 * @return The value of the percentage denominator
	 **/
	function getPercentageDenominator() external pure returns (uint256) {
		return PERCENTAGE_DENOMINATOR;
	}

	function _authorizeUpgrade(
		address newImplementation
	) internal virtual override onlyOwner {}
}
