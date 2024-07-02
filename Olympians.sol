// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';

import './OlympiansWhitelist.sol';
import '../helpers/PercentageManager.sol';
import '../interfaces/IOlympexTreasury.sol';

import 'hardhat/console.sol';

contract Olympians is Ownable, ERC721, PercentageManager, OlympiansWhitelist {
	using Strings for uint256;

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
	bytes32 public constant GODS_TYPE = keccak256('GODS');
	bytes32 public constant DEMIGODS_TYPE = keccak256('DEMIGODS');

	/// @dev Maximum number of NFTs that can be minted
	uint256 public constant MAX_SUPPLY = 1000;

	/// @dev Maximum number of Gods-type NFTs that can be minted
	uint256 public constant MAX_SUPPLY_GODS = 12;

	/// @dev Maximum number of Demigods-type NFTs that can be minted
	uint256 public constant MAX_SUPPLY_DEMIGODS = 988;

	/// @dev discount percentage applied in private sale
	uint256 public constant PERCENTAGE_DISCOUNT = 1000; // 10%

	/// @dev Total percentage allocated to Gods-type NFTs from dividends
	uint256 public constant PERCENTAGE_PER_NFT_GODS = 7000; // 70%

	/// @dev Total percentage allocated to Demigods-type NFTs from dividends
	uint256 public constant PERCENTAGE_PER_NFT_DEMIGODS = 3000; // 30%

	/// @dev Selling price of Gods-type NFTs
	uint256 public constant PRICE_PER_NFT_GODS = 0.09 ether;

	/// @dev Selling price of Demigods-type NFTs
	uint256 public constant PRICE_PER_NFT_DEMIGODS = 0.09 ether;

	/// @dev The date when the private presale ends
	uint256 public constant PRESALE_FINISH_AT = 1711752223;

	/// @dev The date when the private presale begins
	uint256 public constant PRESALE_INITIALIZED_AT = 1709246623;

	/// @dev Base URL for NFT metadata
	string private _nftURI = 'https://olympex.defi';

	/// @dev Counter of minted NFT identifiers
	uint256 private _tokenIdCounter;

	/// @dev Counter of minted Gods-type NFTs
	uint256 private _godsCounter;

	/// @dev Counter of minted Demigods-type NFTs
	uint256 private _demigodsCounter;

	/// @dev Counter of minted Demigods-type NFTs
	IOlympexTreasury private OlympexTreasury;

	/***************
	 * 3. MAPPINGS *
	 ***************/
	// empty

	/*************
	 * 4. Events *
	 *************/
	// empty

	/****************
	 * 5. MODIFIERS *
	 ****************/
	modifier definedTreasury() {
		require(address(OlympexTreasury) != address(0), 'undefined treasury');
		_;
	}

	/****************
	 * 5. FUNCTIONS *
	 ****************/
	/**
	 * @param name_ Name of the NFT collection
	 * @param symbol_ Symbol of the NFT collection
	 * @param signerAddress_ Wallet address authorized to sign backend transactions
	 **/
	constructor(
		string memory name_,
		string memory symbol_,
		address signerAddress_
	) Ownable(msg.sender) ERC721(name_, symbol_) OlympiansWhitelist(signerAddress_) {
		require(MAX_SUPPLY_DEMIGODS + MAX_SUPPLY_GODS == MAX_SUPPLY, 'Invalid supply');

		require(
			PERCENTAGE_PER_NFT_GODS + PERCENTAGE_PER_NFT_DEMIGODS == PERCENTAGE_DENOMINATOR,
			'Invalid percentage'
		);
	}

	function setTreasury(IOlympexTreasury OlympexTreasury_) external onlyOwner {
		require(address(OlympexTreasury) == address(0), 'Treasury was already defined');
		OlympexTreasury = OlympexTreasury_;
	}

	function withdraw() external onlyOwner {
		payable(msg.sender).transfer(address(this).balance);
	}

	function setBaseURI(string memory nftURI_) external onlyOwner {
		_nftURI = nftURI_;
	}

	function tokenURI(
		uint256 tokenId_
	) public view virtual override returns (string memory) {
		_requireOwned(tokenId_);
		return string(abi.encodePacked(_nftURI, '/', tokenId_.toString(), '.json'));
	}

	/**
	 * @dev Mints NFT with type `nftType_` and transfers it to `msg.sender`
	 * @param nftType_ Type of NFT to be minted
	 **/
	function mint(bytes32 nftType_) external payable definedTreasury {
		require(nftType_ == GODS_TYPE || nftType_ == DEMIGODS_TYPE, 'type not allowed');
		require(block.timestamp >= PRESALE_FINISH_AT, 'Sale has not yet started');

		uint256 _tokenId = ++_tokenIdCounter;
		require(_tokenId <= MAX_SUPPLY, 'Fulfilled supply');

		(uint256 _price, uint256 _percentage) = calculatePriceAndPercentage(nftType_, false);

		require(_price > 0 && msg.value == _price, 'Incorent ETH value sent');

		_safeMint(msg.sender, _tokenId);
		OlympexTreasury.setNFTPercentage(_tokenId, _percentage);
	}

	/**
	 * @dev Mints NFT with type `nftType_` and transfers it to `msg.sender`
	 * @param nftType_ Type of NFT to be minted
	 * @param signature_ Sign to verify if you are authorized to mint
	 **/
	function mintPresale(
		bytes32 nftType_,
		bytes memory signature_
	) external payable definedTreasury {
		require(nftType_ == GODS_TYPE || nftType_ == DEMIGODS_TYPE, 'type not allowed');
		require(PRESALE_FINISH_AT <= block.timestamp, 'The pre-sale has already finished');
		require(
			PRESALE_INITIALIZED_AT >= block.timestamp,
			'The pre-sale has not yet started'
		);

		require(verifyMinterSigner(nftType_, signature_), 'SIGNATURE_VALIDATION_FAILED');

		uint256 _tokenId = ++_tokenIdCounter;

		require(_tokenId <= MAX_SUPPLY, 'Fulfilled supply');

		(uint256 _price, uint256 _percentage) = calculatePriceAndPercentage(nftType_, true);

		require(_price > 0 && msg.value == _price, 'Incorent ETH value sent');

		_safeMint(msg.sender, _tokenId);
		OlympexTreasury.setNFTPercentage(_tokenId, _percentage);
	}

	function currentCount() public view returns (uint256) {
		return _tokenIdCounter;
	}

	function currentGodsCounter() public view returns (uint256) {
		return _godsCounter;
	}

	function currentDemigodsCounter() public view returns (uint256) {
		return _demigodsCounter;
	}

	/**
	 * @dev Calculate the price of an NFT according to its type and the percentage that
	 * corresponds to the dividends
	 * @param nftType_ Type of NFT to be minted
	 * @param isPresale_ Determines whether the price should be calculated for a common
	 * pre-sale or sale
	 **/
	function calculatePriceAndPercentage(
		bytes32 nftType_,
		bool isPresale_
	) internal returns (uint256 _price, uint256 _percentage) {
		if (nftType_ == GODS_TYPE) {
			_godsCounter++;
			require(_godsCounter <= MAX_SUPPLY_GODS, 'Fulfilled Gods-type supply');

			_price =
				PRICE_PER_NFT_GODS -
				(isPresale_ ? (PRICE_PER_NFT_GODS * PERCENTAGE_DISCOUNT) : 0);
			_percentage = PERCENTAGE_PER_NFT_GODS / MAX_SUPPLY_GODS;
		}

		if (nftType_ == DEMIGODS_TYPE) {
			_demigodsCounter++;
			require(_demigodsCounter <= MAX_SUPPLY_DEMIGODS, 'Fulfilled Demigods-type supply');

			_price =
				PRICE_PER_NFT_DEMIGODS -
				(isPresale_ ? (PRICE_PER_NFT_DEMIGODS * PERCENTAGE_DISCOUNT) : 0);
			_percentage = PERCENTAGE_PER_NFT_DEMIGODS / MAX_SUPPLY_DEMIGODS;
		}
	}
}
