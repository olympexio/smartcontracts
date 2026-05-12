// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <=0.8.24;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';
import { UUPSUpgradeable } from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { AccessControlUpgradeable } from '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import { ReentrancyGuardUpgradeable } from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';

import { UniversalERC20 } from './libraries/UniversalERC20.sol';
import { IPartnersTreasury } from './interfaces/IPartnersTreasury.sol';
import { RevertReasonParser } from './libraries/RevertReasonParser.sol';

contract PartnersTreasury is
	IPartnersTreasury,
	AccessControlUpgradeable,
	ReentrancyGuardUpgradeable,
	UUPSUpgradeable
{
	using Strings for uint256;
	using UniversalERC20 for IERC20;

	/*********
	 * INDEX *
	 *********/
	// 1. Constants and variables.
	// 2. mappings.
	// 3. Functions.

	/******************************
	 * 1. CONSTANTS AND VARIABLES *
	 ******************************/
	bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
	bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE');
	bytes32 public constant AUTOMATOR_ROLE = keccak256('AUTOMATOR_ROLE');

	/// @dev Token address where dividends are paid to partners
	IERC20 public paymentToken;
	uint256 public settlementNonce;
	address public feeDistributor;
	uint256 public destinationChainId;

	/// @dev storage gaps for contract upgrade
	uint256[50] __gap_PartnersTreasury;

	/***************
	 * 2. MAPPINGS *
	 ***************/
	/**
	 * @dev Record of balances by partners in the payment token (USDT)
	 * on the main chain (polygon) to make claims
	 * partner => balance
	 **/
	mapping(address => uint256) public paymentTokenBalances;

	/**
	 * @dev Settlements registered on main chain (Polygon)
	 * settlementId => CrossChainSettlement
	 **/
	mapping(bytes32 => CrossChainSettlement) public crossChainSettlements;

	/**
	 * @dev Partner balances in local tokens (on origin networks)
	 * partner => token => balance
	 **/
	mapping(address => mapping(IERC20 => uint256)) public partnerTokenBalances;

	/****************
	 * 3. FUNCTIONS *
	 ****************/
	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	/**
	 * @param feeDistributor_ Address of the contract that distributes fees to partners
	 * @param paymentToken_ Token address where dividends are paid to holders
	 **/
	function __PartnersTreasury_int(
		address feeDistributor_,
		IERC20 paymentToken_,
		uint256 destinationChainId_
	) external initializer {
		__AccessControl_init();
		__UUPSUpgradeable_init();

		if (address(feeDistributor_) == address(0)) revert InvalidFeeDistributor();
		if (address(paymentToken_) == address(0)) revert InvalidPaymentToken();

		_grantRole(ADMIN_ROLE, msg.sender);
		_grantRole(UPGRADER_ROLE, msg.sender);
		_grantRole(AUTOMATOR_ROLE, msg.sender);
		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

		feeDistributor = feeDistributor_;
		paymentToken = paymentToken_;
		destinationChainId = destinationChainId_;
	}

	receive() external payable {}

	function getVersion() external pure returns (string memory) {
		return 'v1.0.0';
	}

	function setPaymentToken(IERC20 paymentToken_) external onlyRole(ADMIN_ROLE) {
		if (address(paymentToken_) == address(0)) revert InvalidPaymentToken();

		emit ChangePaymentToken(address(paymentToken = paymentToken_));
	}

	function setDestinationChainId(
		uint256 destinationChainId_
	) external onlyRole(ADMIN_ROLE) {
		emit ChangeDestinationChainId(destinationChainId = destinationChainId_);
	}

	// ========== Functions in Networks Origin ========== //

	function setFeeDistributor(address feeDistributor_) external onlyRole(ADMIN_ROLE) {
		if (address(feeDistributor_) == address(0)) revert InvalidFeeDistributor();

		emit SetFeeDistributor(feeDistributor = feeDistributor_);
	}

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
	) external payable {
		require(
			token_.isETH() ? msg.value == amount_ : msg.value == 0,
			'Incorrect msg.value'
		);

		require(
			msg.sender == feeDistributor,
			'PartnersTreasury: Unauthorized fee distribution'
		);

		if (!token_.isETH()) {
			token_.universalTransferFrom(msg.sender, address(this), amount_);
		}

		partnerTokenBalances[partner_][token_] += amount_;
		emit FeesDistributed(partner_, token_, amount_);
	}

	/**
	 * @dev The main function of this method is to make a swap or a crossChain swap to move
	 * any token in possession of the treasurer (this) to the chief treasurer as the
	 * destination for the payment token.
	 * @param partner_ Address of the partner to whom the funds will be transferred for liquidation
	 * @param aggregator_ Address of the contract in charge of making the swap/crossChainSwap
	 * @param middleware_ The address of middleware that make the swap used for the aggregator
	 * @param data_ calldata required to call the aggregator
	 * @param desc_ SwapDescription struct containing swap details and parameters
	 **/
	function swapToPaymentToken(
		address partner_,
		address aggregator_,
		address middleware_,
		bytes calldata data_,
		SwapDescription calldata desc_
	) external payable onlyRole(AUTOMATOR_ROLE) {
		if (address(partner_) == address(0)) revert InvalidPartnerAddress();
		if (address(aggregator_) == address(0)) revert InvalidAggregatorAddress();

		uint256 initialBalance = desc_.srcToken.universalBalanceOf(address(this));

		if (initialBalance < desc_.amount) revert InsufficientBalanceInContract();

		if (partnerTokenBalances[partner_][desc_.srcToken] < desc_.amount)
			revert InsufficientBalanceToPartner();

		if (!desc_.srcToken.isETH()) {
			desc_.srcToken.universalApprove(middleware_, desc_.amount);
		}

		(bool success, bytes memory returnData) = address(aggregator_).call{
			value: desc_.value
		}(data_);

		if (!success) {
			string memory errorMessage = RevertReasonParser.parse(
				returnData,
				'swapToPaymentToken external call failed: '
			);

			revert(errorMessage);
		}

		uint256 spent = initialBalance - desc_.srcToken.universalBalanceOf(address(this));

		if (spent > desc_.amount) revert SpentToMuch();

		partnerTokenBalances[partner_][desc_.srcToken] -= spent;

		emit CrossChainSettlementCreated(
			// Generate unique settlementId for partner/token
			keccak256(abi.encode(block.chainid, settlementNonce++, partner_, desc_.srcToken)),
			partner_,
			desc_.srcToken,
			desc_.amount,
			destinationChainId
		);
	}

	// ========== Functions in Polygon ========== //

	function executeSettlement(
		bytes32 settlementId_,
		uint256 receivedAmount_,
		CrossChainSettlement calldata settlement_
	) external onlyRole(AUTOMATOR_ROLE) {
		require(
			block.chainid == destinationChainId,
			string(abi.encodePacked('Can only be called in ', destinationChainId.toString()))
		);

		CrossChainSettlement storage settlement = crossChainSettlements[settlementId_];

		if (settlement.partner != address(0)) revert SettlementAlreadyExists();

		settlement.partner = settlement_.partner;
		settlement.sourceChainId = settlement_.sourceChainId;
		settlement.srcToken = settlement_.srcToken;
		settlement.srcAmount = settlement_.srcAmount;

		crossChainSettlements[settlementId_] = settlement;

		paymentTokenBalances[settlement.partner] += receivedAmount_;

		emit CompleteSettlement(settlementId_, receivedAmount_);
	}

	/**
	 * @dev Claim accumulated earnings
	 **/
	function claim() external nonReentrant {
		uint256 amount = paymentTokenBalances[msg.sender];
		if (amount == 0) revert HasNothingToClaim();

		paymentTokenBalances[msg.sender] = 0;
		paymentToken.universalTransfer(payable(msg.sender), amount);

		emit Claimed(msg.sender, amount);
	}

	function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}
}
