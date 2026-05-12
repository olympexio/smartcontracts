// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <=0.8.24;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { ECDSA } from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import { MessageHashUtils } from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import { UUPSUpgradeable } from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import { AccessControlUpgradeable } from '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IERC721 } from '@openzeppelin/contracts/token/ERC721/IERC721.sol';

import { UniversalERC20 } from './libraries/UniversalERC20.sol';
import { IOlympiansTreasury } from './interfaces/IOlympiansTreasury.sol';
import { PercentageManager } from './helpers/PercentageManager.sol';
import { RevertReasonParser } from './libraries/RevertReasonParser.sol';

contract OlympiansTreasury is
	PercentageManager,
	IOlympiansTreasury,
	AccessControlUpgradeable,
	UUPSUpgradeable
{
	using ECDSA for bytes32;
	using UniversalERC20 for IERC20;
	using MessageHashUtils for bytes32;

	/*********
	 * INDEX *
	 *********/
	// 1. Type declarations.
	// 2. Constants and variables.
	// 3. mappings.
	// 4. Events.
	// 5. modifiers.
	// 6. Functions.

	/************************
	 * 1. TYPE DECLARATIONS *
	 ************************/
	struct SwapDescription {
		uint256 value;
		uint256 amount;
		IERC20 srcToken;
	}

	/******************************
	 * 2. CONSTANTS AND VARIABLES *
	 ******************************/
	bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
	bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE');
	bytes32 public constant AUTOMATOR_ROLE = keccak256('AUTOMATOR_ROLE');

	/// @dev Wallet address authorized to sign backend transactions for onchain validation.
	address internal _signerAddress;

	/// @dev Token address where dividends are paid to holders
	IERC20 public paymentToken;

	/// @dev Address of the NFT contract allowed to claim dividends
	IERC721 public Olympians;

	/// @dev Tracks or records claims from all holders
	uint256 private _claimTracker;

	/***************
	 * 3. MAPPINGS *
	 ***************/
	/// @dev It alludes to the portion of the token percentage assigned to each NFT holder
	// NFT ID => percentage
	mapping(uint256 => uint256) public nftRewardsAllocation;

	/// @dev Tracks or records claims from each holder
	// Address of the holder => Total tokens claimed
	mapping(address => uint256) private _claimTrackerByAddress;

	/*************
	 * 4. Events *
	 *************/
	// empty

	/****************
	 * 5. MODIFIERS *
	 ****************/
	/// @dev Thrown if called to function where Olympians is not defined
	modifier checkOlympiansDefined() {
		require(block.chainid == uint(137), 'Only allow in chainId in polygon');
		require(address(Olympians) != address(0), 'Olympians is not set');
		_;
	}

	/// @dev Thrown if called by any account other than the NFT contract
	modifier onlyOlympians() {
		require(msg.sender == address(Olympians), 'Unauthorized');
		_;
	}

	/// @dev Thrown if called by any account other than an account holder
	modifier onlyHolder(uint256 tokenId_) {
		require(msg.sender == Olympians.ownerOf(tokenId_), 'Is not a holder');
		_;
	}

	/****************
	 * 6. FUNCTIONS *
	 ****************/
	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	/**
	 * @param paymentToken_ Token address where dividends are paid to holders
	 * @param signerAddress_ Wallet address authorized to sign backend transactions
	 **/
	function initialize(IERC20 paymentToken_, address signerAddress_) public initializer {
		__AccessControl_init();
		__UUPSUpgradeable_init();
		if (address(paymentToken_) == address(0)) revert InvalidPaymentToken();
		if (signerAddress_ == address(0)) revert InvalidSignerAddress();

		__OlympiansTreasury_init_unchained(paymentToken_, signerAddress_);

		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_grantRole(ADMIN_ROLE, msg.sender);
		_grantRole(UPGRADER_ROLE, msg.sender);
		_grantRole(AUTOMATOR_ROLE, msg.sender);
	}

	function __OlympiansTreasury_init_unchained(
		IERC20 paymentToken_,
		address signerAddress_
	) internal onlyInitializing {
		paymentToken = paymentToken_;
		_signerAddress = signerAddress_;
	}

	function setOlympians(IERC721 olympians_) external onlyRole(ADMIN_ROLE) {
		if (block.chainid != uint(137)) revert OnlyPolygonAllow();
		if (address(olympians_) == address(0)) revert InvalidOlympiansAddress();

		Olympians = olympians_;
	}

	receive() external payable {}

	function getVersion() external pure returns (string memory) {
		return 'v1.0.0';
	}

	function setPaymentToken(IERC20 paymentToken_) external onlyRole(ADMIN_ROLE) {
		paymentToken = paymentToken_;
		emit ChangePaymentToken(paymentToken);
	}

	/**
	 * @dev Set the percentage of dividends allocated to the NFT holder. This method will
	 * only be used in the network where the investment NFT contract is deployed, in the
	 * rest of the networks the `swapToPaymentToken` method must be used to send the
	 * collected fees to the treasurer contract in the network where the NFT contract is deployed.
	 * @param tokenId_ NFT identifier
	 * @param percentage_ Percentage of dividends assigned to `tokenId_`
	 **/
	function setNFTPercentage(
		uint256 tokenId_,
		uint256 percentage_
	) external checkOlympiansDefined onlyOlympians validPercentage(percentage_) {
		nftRewardsAllocation[tokenId_] = percentage_;

		emit SetNFTPercentage(tokenId_, percentage_);
	}

	/**
	 * @dev Claim accumulated dividends
	 * @param tokenId_ NFT identifier
	 **/
	function claim(uint256 tokenId_) external checkOlympiansDefined onlyHolder(tokenId_) {
		uint256 _claimableAmount = calculateClaimableAmount(tokenId_);
		require(_claimableAmount > 0, 'No income available to claim');

		_claimTracker += _claimableAmount;
		_claimTrackerByAddress[msg.sender] += _claimableAmount;

		paymentToken.universalTransfer(payable(msg.sender), _claimableAmount);

		emit Claimed(msg.sender, _claimableAmount);
	}

	/**
	 * @dev The main function of this method is to make a swap or a crossChain swap to move
	 * any token in possession of the treasurer (this) to the chief treasurer as the
	 * destination for the payment token.
	 * @param aggregator_ Address of the contract in charge of making the swap/crossChainSwap
	 * @param middleware_ The address of middleware that make the swap used for the aggregator
	 * @param desc_ SwapDescription struct containing swap details and parameters
	 * @param data_ calldata required to call the aggregator
	 **/
	function swapToPaymentToken(
		address aggregator_,
		address middleware_,
		SwapDescription calldata desc_,
		bytes calldata data_
	) external payable onlyRole(AUTOMATOR_ROLE) {
		require(
			desc_.srcToken.universalBalanceOf(address(this)) >=
				(desc_.srcToken.isETH() ? desc_.value : desc_.amount),
			'Insufficient balance'
		);

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

		emit SwappedToPaymentToken(
			aggregator_,
			address(desc_.srcToken),
			address(paymentToken),
			desc_.amount,
			data_
		);
	}

	/**
	 * @dev Calculate the amount of tokens that an NFT holder can claim
	 * @param tokenId_ NFT identifier
	 **/
	function calculateClaimableAmount(
		uint256 tokenId_
	) internal view checkOlympiansDefined returns (uint256) {
		uint256 _percentage = nftRewardsAllocation[tokenId_];

		address beneficiary = Olympians.ownerOf(tokenId_);

		// How much the owner of the token has already claimed in rewards.
		uint256 _alreadyClaimed = _claimTrackerByAddress[beneficiary];

		uint256 _totalRevenue = (dividendBalanceStored() * _percentage) /
			PERCENTAGE_DENOMINATOR;

		return _totalRevenue - _alreadyClaimed;
	}

	/// @dev Total balance of dividends earned throughout history
	function dividendBalanceStored() internal view returns (uint256) {
		return _claimTracker + paymentToken.balanceOf((address(this)));
	}

	function verifySigner(
		uint256 amount_,
		IERC20 srcToken_,
		IERC20 outToken_,
		address recipient_,
		bytes calldata signature_
	) internal view returns (bool) {
		return
			keccak256(abi.encodePacked(amount_, srcToken_, outToken_, recipient_))
				.toEthSignedMessageHash()
				.recover(signature_) == _signerAddress;
	}

	function _authorizeUpgrade(
		address newImplementation
	) internal override onlyRole(UPGRADER_ROLE) {}
}
