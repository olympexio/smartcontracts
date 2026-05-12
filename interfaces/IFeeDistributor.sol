// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <=0.8.24;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IPartnersTreasury } from './IPartnersTreasury.sol';

interface IFeeDistributor {
	struct FeeDescription {
		address partner;
		bool isReferredB2B;
		uint256 discountRate;
		uint256 partnerPercentage;
	}

	error InvalidOlympexTreasury();
	error InvalidSignerAddress();
	error FeesShouldNotBe0();
	error CannotBeZeroAddress();

	event FeesDistributed(
		IERC20 indexed token,
		address indexed beneficiary,
		uint256 amount
	);

	event DiscountRefund(
		IERC20 indexed token,
		address indexed beneficiary,
		uint256 discount
	);

	event SetOlympiansTreasury(address indexed olympiansTreasury_);

	event SetOlympexTreasury(address indexed olympexTreasury_);

	event SetPlatformFee(uint256 platformFee_);

	event SetFeePercentage(uint256 olympexFee_);

	event SetSignerAddress(address indexed signerAddress);

	event ChangePartnersTreasury(IPartnersTreasury indexed partnersTreasury_);

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
	) external payable;

	function platformFee() external view returns (uint256);

	/// @notice Returns the percentage denominator used for percentage calculations
	/// @return The value of the percentage denominator
	function getPercentageDenominator() external pure returns (uint256);
}
