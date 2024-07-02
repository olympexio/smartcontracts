// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';

import './helpers/PercentageManager.sol';
import './interfaces/IOlympexAggregator.sol';

contract OlympiansTreasury is PercentageManager {
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
	// empty

	/******************************
	 * 2. CONSTANTS AND VARIABLES *
	 ******************************/
	/// @dev Token address where dividends are paid to holders
	IERC20 public paymentToken;

	/// @dev Address of the NFT contract allowed to claim dividends
	IERC721 public nftContractAddress;

	// TODO: al momento de deployar en mainnet esto se puede convertir en una constante
	// para optimizar el consumo de gas
	/// @dev Address of the swap contract
	IOlympexAggregator private OlympexAggregator;

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
	/// @dev dividend payment claimed
	event Claimed(address indexed beneficiary_, uint256 amount_);

	/****************
	 * 5. MODIFIERS *
	 ****************/
	/// @dev Thrown if called by any account other than the NFT contract
	modifier onlyContratNFT() {
		require(msg.sender == address(nftContractAddress), 'Unauthorized');
		_;
	}

	/// @dev Thrown if called by any account other than an account holder
	modifier onlyHolder(uint256 tokenId_) {
		require(msg.sender == nftContractAddress.ownerOf(tokenId_), 'Is not a holder');
		_;
	}

	/****************
	 * 5. FUNCTIONS *
	 ****************/
	/**
	 * @param paymentToken_ Token address where dividends are paid to holders
	 * @param nftContractAddress_ Address of the NFT contract allowed to claim dividends
	 * @param OlympexAggregator_ Address of the swap contract
	 **/
	constructor(
		IERC20 paymentToken_,
		IERC721 nftContractAddress_,
		IOlympexAggregator OlympexAggregator_
	) {
		paymentToken = paymentToken_;
		OlympexAggregator = OlympexAggregator_;
		nftContractAddress = nftContractAddress_;
	}

	/**
	 * @dev Set the percentage of dividends allocated to the NFT holder
	 * @param tokenId_ NFT identifier
	 * @param percentage_ Percentage of dividends assigned to `tokenId_`
	 **/
	function setNFTPercentage(
		uint256 tokenId_,
		uint256 percentage_
	) external onlyContratNFT validPercentage(percentage_) {
		nftRewardsAllocation[tokenId_] = percentage_;
	}

	/**
	 * @dev Claim accumulated dividends
	 * @param tokenId_ NFT identifier
	 **/
	function claim(uint256 tokenId_) external onlyHolder(tokenId_) {
		uint256 _claimableAmount = calculateClaimableAmount(tokenId_);
		require(_claimableAmount > 0, 'No income available to claim');

		uint256 _currentBalance = paymentToken.balanceOf((address(this)));

		uint256 _amountPayable = _currentBalance < _claimableAmount
			? _currentBalance
			: _claimableAmount;

		_claimTracker += _amountPayable;
		_claimTrackerByAddress[msg.sender] += _amountPayable;

		paymentToken.transfer(msg.sender, _amountPayable);

		emit Claimed(msg.sender, _amountPayable);
	}

	/**
	 * @dev Calculate the amount of tokens that an NFT holder can claim
	 * @param tokenId_ NFT identifier
	 **/
	function calculateClaimableAmount(uint256 tokenId_) internal view returns (uint256) {
		uint256 _percentage = nftRewardsAllocation[tokenId_];

		address beneficiary = nftContractAddress.ownerOf(tokenId_);

		uint256 _alreadyClaimed = _claimTrackerByAddress[beneficiary];

		uint256 _totalRevenue = (dividendBalanceStored() * _percentage) /
			PERCENTAGE_DENOMINATOR;

		return _totalRevenue > _alreadyClaimed ? _totalRevenue - _alreadyClaimed : 0;
	}

	/// @dev Total balance of dividends earned throughout history
	function dividendBalanceStored() internal view returns (uint256) {
		return _claimTracker + paymentToken.balanceOf((address(this)));
	}
}
