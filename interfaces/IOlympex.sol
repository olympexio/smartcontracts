// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <=0.8.24;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { IFeeDistributor } from './IFeeDistributor.sol';

interface IOlympex {
	/**********
	 * Errors *
	 **********/
	error SwapExpired();
	error FundsNotReceived();
	error CannotSwapSameToken();
	error InvalidSwapSignature();
	error MinReturnShouldNotBe0();
	error ReturnAmountIsNotEnough();
	error RouterNotSet();
	error FeeDistributorNotSet();
	error InvalidRouter();
	error InvalidFeeDistributor();
	error InvalidSignerAddress();

	/// @dev Structure to store details of a swap operation.
	struct SwapDescription {
		uint256 toChainId;
		IERC20 srcToken;
		IERC20 dstToken;
		address srcReceiver;
		address dstReceiver;
		uint256 amount;
		uint256 minReturnAmount;
		uint256 guaranteedAmount;
		uint256 tradedVolume;
		uint256 nftPoints;
		uint256 tokenId;
		uint256 nftType;
		bytes signature;
		uint256 expiredIn;
	}

	struct SwapParams {
		string dexName;
		bytes data;
		bytes extraData;
		SwapDescription description;
		IFeeDistributor.FeeDescription feeDescription;
	}

	/**********
	 * Events *
	 **********/
	event RescueFunds(IERC20 indexed token, uint256 amount);

	event SetMinTradeVolume(uint256 minTradeVolume);

	event SetRouter(address indexed router_);

	event SetSignerAddress(address indexed signerAddress_);

	event SetFeeDistributor(IFeeDistributor indexed feeDistributor);

	/**
	 * @dev Emitted when a swap occurs
	 * @param dexName DEX name
	 * @param dstReceiver Address receiving the destination tokens
	 * @param srcToken Source token being swapped
	 * @param dstToken Destination token received in the swap
	 * @param toChainId destination chain ID
	 * @param tradedVolume Volume traded by user
	 * @param spentAmount Total amount spent (source tokens + fees)
	 * @param guaranteedAmount Amount that the user is guaranteed to receive, what they
	 * actually receive fluctuates between guaranteedAmount and minReturnAmount
	 * @param returnAmount Amount of destination tokens received
	 * @param nftPoints Number of points accumulated in the swap
	 * @param tokenId NFT numerical identifier
	 * @param nftType NFT type or level. This determines the level of discount granted to the user
	 **/
	event Swapped(
		string indexed dexName,
		address indexed dstReceiver,
		IERC20 srcToken,
		IERC20 dstToken,
		uint256 toChainId,
		uint256 tradedVolume,
		uint256 spentAmount,
		uint256 guaranteedAmount,
		uint256 returnAmount,
		uint256 nftPoints,
		uint256 tokenId,
		uint256 nftType
	);

	/**
	 * @dev Executes a token swap operation, allowing users to exchange tokens on Olympex
	 **/
	function swap(
		SwapParams calldata params
	) external payable returns (uint256 returnAmount);

	function crossSwap(SwapParams calldata params) external payable;
}
