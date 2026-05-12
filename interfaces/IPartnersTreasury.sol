// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <=0.8.24;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IPartnersTreasury {
	error SpentToMuch();
	error HasNothingToClaim();
	error SettlementAlreadyExists();
	error InsufficientBalanceToPartner();
	error InsufficientBalanceInContract();

	struct CrossChainSettlement {
		address partner;
		uint256 sourceChainId;
		IERC20 srcToken;
		uint256 srcAmount;
	}

	struct SwapDescription {
		uint256 value;
		uint256 amount;
		IERC20 srcToken;
	}

	event FeesDistributed(address partner, IERC20 token, uint256 amount);

	event CrossChainSettlementCreated(
		bytes32 settlementId,
		address partner,
		IERC20 srcToken,
		uint256 srcAmount,
		uint256 toChainId
	);

	event SetFeeDistributor(address feeDistributor);

	event ChangePaymentToken(address paymentToken);

	event ChangeDestinationChainId(uint256 destinationChainId);

	event CompleteSettlement(bytes32 settlementId, uint256 paymentAmount);

	/// @dev claimed earnings
	event Claimed(address indexed partner_, uint256 amount_);

	error InvalidFeeDistributor();

	error InvalidPaymentToken();

	error InvalidPartnerAddress();

	error InvalidAggregatorAddress();

	/**
	 * @dev Distribute fees to a partner (called ONLY by FeeDistributor) Accumulate balances
	 * on the CURRENT network (eg: DAI on Ethereum, BUSD on BSC)
	 * @param partner_ Address of the partner to whom the fees belong
	 * @param token_ Token address where fees are paid
	 * @param amount_ amount of tokens paid
	 **/
	function distributeFeesToPartner(
		address partner_,
		IERC20 token_,
		uint256 amount_
	) external payable;
}
