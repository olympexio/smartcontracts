// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { UUPSUpgradeable } from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import { ReentrancyGuardUpgradeable } from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import { AccessControlUpgradeable } from '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import { IPartnerBonusVault } from './interfaces/IPartnerBonusVault.sol';

/// @title PartnerBonusVault
/// @notice Holds ERC20 bonus funds and pays partners per milestone.
contract PartnerBonusVault is
	IPartnerBonusVault,
	AccessControlUpgradeable,
	UUPSUpgradeable,
	ReentrancyGuardUpgradeable
{
	using SafeERC20 for IERC20;

	bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
	bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE');
	bytes32 public constant AUTOMATOR_ROLE = keccak256('AUTOMATOR_ROLE');

	/// @dev keccak256(abi.encode(partner, milestoneNumber)) => paid
	mapping(bytes32 => bool) public paidMilestones;

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	function __PartnerBonusVault_init() external initializer {
		__AccessControl_init();
		__ReentrancyGuard_init();
		__UUPSUpgradeable_init();

		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_grantRole(ADMIN_ROLE, msg.sender);
		_grantRole(UPGRADER_ROLE, msg.sender);
		_grantRole(AUTOMATOR_ROLE, msg.sender);
	}

	function getVersion() external pure virtual returns (string memory) {
		return 'v1.0.0';
	}

	function deposit(
		IERC20 token,
		uint256 amount
	) external onlyRole(ADMIN_ROLE) nonReentrant {
		if (amount == 0) revert InvalidAmount();
		token.safeTransferFrom(msg.sender, address(this), amount);
		emit FundsDeposited(address(token), amount, msg.sender);
	}

	function withdraw(
		IERC20 token,
		uint256 amount,
		address to
	) external onlyRole(ADMIN_ROLE) nonReentrant {
		if (amount == 0) revert InvalidAmount();
		if (to == address(0)) revert InvalidWithdrawRecipient();
		uint256 bal = token.balanceOf(address(this));
		if (bal < amount) revert InsufficientVaultBalance();
		token.safeTransfer(to, amount);
		emit FundsWithdrawn(address(token), amount, to);
	}

	function payBonus(
		address partner,
		uint256 milestoneNumber,
		IERC20 token,
		uint256 amount
	) external onlyRole(AUTOMATOR_ROLE) nonReentrant {
		_payBonus(partner, milestoneNumber, token, amount);
	}

	function payBonusBatch(
		BonusPayment[] calldata payments
	) external onlyRole(AUTOMATOR_ROLE) nonReentrant {
		uint256 len = payments.length;
		for (uint256 i = 0; i < len; ) {
			BonusPayment calldata p = payments[i];
			_payBonus(p.partner, p.milestoneNumber, p.token, p.amount);
			unchecked {
				++i;
			}
		}
	}

	function _payBonus(
		address partner,
		uint256 milestoneNumber,
		IERC20 token,
		uint256 amount
	) internal {
		if (partner == address(0)) revert InvalidPartnerAddress();
		if (amount == 0) revert InvalidAmount();

		bytes32 milestoneId = keccak256(abi.encode(partner, milestoneNumber));
		if (paidMilestones[milestoneId]) revert MilestoneAlreadyPaid(milestoneId);

		uint256 bal = token.balanceOf(address(this));
		if (bal < amount) revert InsufficientVaultBalance();

		paidMilestones[milestoneId] = true;
		token.safeTransfer(partner, amount);

		emit BonusPaid(partner, milestoneNumber, address(token), amount, milestoneId);
	}

	function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}
}
