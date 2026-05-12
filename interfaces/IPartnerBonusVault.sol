// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IPartnerBonusVault {
	struct BonusPayment {
		address partner;
		uint256 milestoneNumber;
		IERC20 token;
		uint256 amount;
	}

	event BonusPaid(
		address indexed partner,
		uint256 indexed milestoneNumber,
		address token,
		uint256 amount,
		bytes32 milestoneId
	);

	event FundsDeposited(address indexed token, uint256 amount, address indexed depositor);

	event FundsWithdrawn(address indexed token, uint256 amount, address indexed to);

	error MilestoneAlreadyPaid(bytes32 milestoneId);
	error InvalidPartnerAddress();
	error InvalidAmount();
	error InvalidWithdrawRecipient();
	error InsufficientVaultBalance();
}
