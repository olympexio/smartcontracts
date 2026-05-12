// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <=0.8.24;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { IFeeDistributor } from './IFeeDistributor.sol';

interface ICrossChainAggregator {
	struct SwapDescription {
		IERC20 srcToken;
		IERC20 dstToken;
		uint256 fromChainId;
		uint256 toChainId;
		address srcReceiver;
		address dstReceiver;
		uint256 amount;
		uint256 minReturnAmount;
		bytes signature;
		uint256 tradedVolume;
		uint256 nftPoints;
		uint256 tokenId;
		uint256 nftType;
		uint256 expiredIn;
	}

	function crossChainSwapDelegatedWithFee(
		address router_,
		SwapDescription calldata desc_,
		IFeeDistributor.FeeDescription calldata feeDescription_,
		bytes calldata data_
	) external payable;
}
