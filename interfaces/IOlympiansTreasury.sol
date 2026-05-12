// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <=0.8.24;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
interface IOlympiansTreasury {
	/// @dev dividend payment claimed
	event Claimed(address indexed beneficiary_, uint256 amount_);

	event ChangePaymentToken(IERC20 indexed prevPaymentToken_);

	event SetNFTPercentage(uint256 indexed tokenId, uint256 percentage_);

	error InvalidSignerAddress();
	error InvalidPaymentToken();
	error OnlyPolygonAllow();
	error InvalidOlympiansAddress();

	event SwappedToPaymentToken(
		address indexed aggregator_,
		address indexed srcToken_,
		address indexed dstToken_,
		uint256 amount_,
		bytes data_
	);

	/**
	 * @dev Set the percentage of dividends allocated to the NFT holder
	 * @param tokenId_ NFT identifier
	 * @param percentage_ Percentage of dividends assigned to `tokenId_`
	 **/
	function setNFTPercentage(uint256 tokenId_, uint256 percentage_) external;
}
