// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <=0.8.24;

import { ECDSA } from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import { MessageHashUtils } from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import { UUPSUpgradeable } from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import { OwnableUpgradeable } from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import { PausableUpgradeable } from '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import { ReentrancyGuardUpgradeable } from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';

import { IERC20, UniversalERC20, SafeERC20 } from './libraries/UniversalERC20.sol';
import { IOlympexRouter } from './interfaces/IOlympexRouter.sol';
import { IFeeDistributor } from './interfaces/IFeeDistributor.sol';

// interfaces
import { IOlympex } from './interfaces/IOlympex.sol';

contract Olympex is
	IOlympex,
	PausableUpgradeable,
	ReentrancyGuardUpgradeable,
	OwnableUpgradeable,
	UUPSUpgradeable
{
	using SafeERC20 for IERC20;
	using UniversalERC20 for IERC20;

	using ECDSA for bytes32;
	using MessageHashUtils for bytes32;

	/***************************
	 * CONSTANTS AND VARIABLES *
	 ***************************/
	/// @dev Define what is the minimum traded volume required to mint Olympex NFTs.
	uint256 public minTradeVolume;

	IFeeDistributor internal FeeDistributor;

	/// @dev Wallet address authorized to sign backend transactions for onchain validation.
	address internal _signerAddress;

	IOlympexRouter public router;

	/************
	 * MAPPINGS *
	 ************/
	/**
	 * @dev Keep a record of a user's accumulated trade volume.
	 * account => cumulative trade volume
	 **/
	mapping(address => uint256) public tradingVolume;

	/**
	 * @dev Keep a record of a user's nonce for signature.
	 * account => cumulative nonce
	 **/
	mapping(address => uint256) public nonce;

	/// @dev storage gaps for contract upgrade
	uint256[50] __gap;

	/*************
	 * FUNCTIONS *
	 *************/
	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	/**
	 * @dev Initializes the OlympexAggregator contract during deployment
	 * @param signerAddress_ Wallet address authorized to sign backend transactions
	 * @param minTradeVolume_ Minimum traded volume required to mint Olympex NFTs
	 * @param feeDistributor_ Address of the fee distributor contract
	 **/
	function initialize(
		address signerAddress_,
		uint256 minTradeVolume_,
		IFeeDistributor feeDistributor_
	) external initializer {
		__Pausable_init();
		__ReentrancyGuard_init();
		__Ownable_init(msg.sender);
		__UUPSUpgradeable_init();

		if (address(0) == address(feeDistributor_)) {
			revert InvalidFeeDistributor();
		}

		if (address(0) == address(signerAddress_)) {
			revert InvalidSignerAddress();
		}

		FeeDistributor = feeDistributor_;
		_signerAddress = signerAddress_;
		minTradeVolume = minTradeVolume_;
	}

	receive() external payable {}

	function getVersion() external pure returns (string memory) {
		return 'v1.0.0';
	}

	function setRouter(address router_) external onlyOwner whenNotPaused {
		if (address(0) == address(router_)) {
			revert InvalidRouter();
		}

		router = IOlympexRouter(router_);
		emit SetRouter(router_);
	}

	function setFeeDistributor(
		IFeeDistributor feeDistributor_
	) external onlyOwner whenNotPaused {
		if (address(0) == address(feeDistributor_)) {
			revert InvalidFeeDistributor();
		}

		emit SetFeeDistributor(FeeDistributor = feeDistributor_);
	}

	function setSignerAddress(address signerAddress_) external onlyOwner whenNotPaused {
		if (address(0) == address(signerAddress_)) {
			revert InvalidSignerAddress();
		}

		emit SetSignerAddress(_signerAddress = signerAddress_);
	}

	function setMinTradeVolume(uint256 minTradeVolume_) external onlyOwner whenNotPaused {
		emit SetMinTradeVolume(minTradeVolume = minTradeVolume_);
	}

	function pause() external onlyOwner {
		_pause();
	}

	function unpause() external onlyOwner {
		_unpause();
	}

	/**
	 * @dev Executes a token swap operation, allowing users to exchange tokens on Olympex
	 **/
	function swap(
		IOlympex.SwapParams calldata params_
	) external payable whenNotPaused nonReentrant returns (uint256 returnAmount) {
		if (params_.description.srcToken == params_.description.dstToken)
			revert CannotSwapSameToken();

		_validateCommon(params_);

		uint256 initialDstBalance = params_.description.dstToken.universalBalanceOf(
			params_.description.dstReceiver
		);

		IOlympexRouter.SwapResult memory swapResult = router.swap{ value: msg.value }(
			params_.dexName,
			IOlympexRouter.SwapParams({
				data: params_.data,
				extraData: params_.extraData,
				description: params_.description,
				feeDescription: params_.feeDescription
			})
		);

		if (swapResult.distributeFees) {
			_ditributesFee(swapResult, params_);
		}

		returnAmount =
			params_.description.dstToken.universalBalanceOf(params_.description.dstReceiver) -
			initialDstBalance;

		if (returnAmount < params_.description.minReturnAmount)
			revert ReturnAmountIsNotEnough();

		nonce[msg.sender] += 1;
		tradingVolume[params_.description.dstReceiver] += params_.description.tradedVolume;

		emit Swapped(
			params_.dexName,
			params_.description.dstReceiver,
			params_.description.srcToken,
			params_.description.dstToken,
			uint256(block.chainid),
			params_.description.tradedVolume,
			params_.description.amount,
			params_.description.guaranteedAmount,
			returnAmount,
			params_.description.nftPoints,
			params_.description.tokenId,
			params_.description.nftType
		);
	}

	function crossSwap(
		IOlympex.SwapParams calldata params_
	) external payable whenNotPaused nonReentrant {
		_validateCommon(params_);

		IOlympexRouter.SwapResult memory swapResult = router.crossSwap{ value: msg.value }(
			params_.dexName,
			IOlympexRouter.SwapParams({
				data: params_.data,
				extraData: params_.extraData,
				description: params_.description,
				feeDescription: params_.feeDescription
			})
		);

		if (swapResult.distributeFees) {
			_ditributesFee(swapResult, params_);
		}

		nonce[msg.sender] += 1;
		tradingVolume[params_.description.dstReceiver] += params_.description.tradedVolume;

		emit Swapped(
			params_.dexName,
			params_.description.dstReceiver,
			params_.description.srcToken,
			params_.description.dstToken,
			params_.description.toChainId,
			params_.description.tradedVolume,
			params_.description.amount,
			params_.description.guaranteedAmount,
			uint256(0), // returnAmount
			params_.description.nftPoints,
			params_.description.tokenId,
			params_.description.nftType
		);
	}

	function _authorizeUpgrade(address) internal override onlyOwner {}

	function _validateCommon(IOlympex.SwapParams calldata params_) internal view {
		if (address(0) == address(router)) revert RouterNotSet();
		if (params_.description.expiredIn < block.timestamp) revert SwapExpired();
		if (params_.description.minReturnAmount <= 0) revert MinReturnShouldNotBe0();
		_verifySignerSwap(params_);
	}

	function _verifySignerSwap(IOlympex.SwapParams calldata params_) internal view {
		if (
			!(keccak256(
				abi.encodePacked(
					params_.dexName,
					params_.description.amount,
					params_.feeDescription.discountRate,
					params_.description.tradedVolume,
					params_.description.srcToken,
					params_.description.dstToken,
					params_.description.dstReceiver,
					params_.description.toChainId,
					nonce[msg.sender],
					uint256(block.chainid),
					params_.description.expiredIn
				)
			).toEthSignedMessageHash().recover(params_.description.signature) == _signerAddress)
		) {
			revert InvalidSwapSignature();
		}
	}

	function _ditributesFee(
		IOlympexRouter.SwapResult memory swapResult,
		IOlympex.SwapParams calldata params_
	) internal {
		uint256 balance = swapResult.paymentToken.universalBalanceOf(address(this));
		if (balance <= 0) revert FundsNotReceived();

		// Calculation of fees, whether to send only the corresponding percentage or the
		// total balance. This depends on each aggregator if they allow us to collect fees
		// directly from their API or not
		uint256 fees = swapResult.feesByPercentage
			? (balance * FeeDistributor.platformFee()) /
				FeeDistributor.getPercentageDenominator()
			: balance;

		// Send the tokens corresponding to the fees to the FeeDistributor for distribution
		swapResult.paymentToken.universalTransfer(payable(address(FeeDistributor)), fees);

		FeeDistributor.distributeFees(
			swapResult.paymentToken,
			params_.description.dstReceiver,
			params_.feeDescription
		);

		if (swapResult.feesByPercentage) {
			// If the fees are calculated from the percentage then the remaining balance is
			// what corresponds to the user for the exchange.
			swapResult.paymentToken.universalTransfer(
				payable(address(params_.description.dstReceiver)),
				balance - fees
			);
		}
	}
}
