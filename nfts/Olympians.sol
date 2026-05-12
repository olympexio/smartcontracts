// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <=0.8.24;

import { OlympiansWhitelist } from './OlympiansWhitelist.sol';
import { PercentageManager } from '../helpers/PercentageManager.sol';
import { IOlympiansTreasury } from '../interfaces/IOlympiansTreasury.sol';

import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { ERC721 } from '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

contract Olympians is ERC721, PercentageManager, OlympiansWhitelist {
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

	/// @dev Maximum number of Demigods-type NFTs that can be minted
	uint256 public MAX_SUPPLY_DEMIGODS = 8_800;

	/// @dev Total percentage allocated to Demigods-type NFTs from dividends
	uint256 public PERCENTAGE_PER_NFT_DEMIGODS;

	/// @dev Earning percentage per God NFT (70% / 12 Gods)
	uint256 public EARNING_PERCENTAGE_PER_GOD;

	/// @dev Earning percentage per Demigod NFT (30% / 988 Demigods)
	uint256 public EARNING_PERCENTAGE_PER_DEMIGOD;

	/// @dev Maximum number of NFTs that can be minted
	uint256 public MAX_SUPPLY = 10_000;

	/// @dev Maximum number of Gods-type NFTs that can be minted
	uint256 public MAX_SUPPLY_GODS = 1_200;

	/// @dev Total percentage allocated to Gods-type NFTs from dividends
	uint256 public PERCENTAGE_PER_NFT_GODS = 700_000; // 70%

	/// @dev Gods-type NFT selling price
	uint256 public PRICE_PER_NFT_GODS = 1 ether;

	/// @dev Gods-type NFT pre-sale price
	uint256 public PRICE_PER_NFT_GODS_PRESALE = 0.9 ether;

	/// @dev Demigods-type NFT selling price
	uint256 public PRICE_PER_NFT_DEMIGODS = 1 ether;

	/// @dev Demigods-type NFT pre-sale price
	uint256 public PRICE_PER_NFT_DEMIGODS_PRESALE = 0.9 ether;

	/// @dev The date when the private presale ends
	uint256 public presaleFinishAt;

	/// @dev The date when the private presale begins
	uint256 public presaleInitializedAt;

	/// @dev Base URL for NFT metadata
	string private _nftURI = 'https://olympex.defi';

	/// @dev Counter of minted NFT identifiers
	uint256 private _tokenIdCounter;

	/// @dev Counter of minted Gods-type NFTs
	uint256 private _godsCounter;

	/// @dev Counter of minted Demigods-type NFTs
	uint256 private _demigodsCounter;

	/// @dev Counter of minted Demigods-type NFTs
	IOlympiansTreasury public OlympiansTreasury;

	/// @dev Variable used for indicate if the variable can be to modify
	bool public freezeVariable = false;

	/***************
	 * 3. MAPPINGS *
	 ***************/
	// empty

	/*************
	 * 4. Events *
	 *************/
	event SetTreasury(address treasury);

	event Withdraw(address indexed sender, uint256 amount);

	event SetBaseURI(string indexed nftURI_);

	event SetMaxSupply(uint256 maxSupply, uint256 maxSupplyGods);

	event SetPercentageNFTGods(
		uint256 percentagePerNFTGods,
		uint256 percentagePerNFTDemigods,
		uint256 earningPercentagePerGod,
		uint256 earningPercentagePerDemigod
	);

	event SetPriceNFTGods(uint256 newPrice);

	event SetPriceNFTGodsPresale(uint256 newPrice);

	event SetPriceNFTDemigods(uint256 newPrice);

	event SetPriceNFTDemigodsPresale(uint256 newPrice);

	event FrozenVariables();

	/****************
	 * 5. MODIFIERS *
	 ****************/
	modifier definedTreasury() {
		require(address(OlympiansTreasury) != address(0), 'undefined treasury');
		_;
	}

	modifier freezable() {
		require(!freezeVariable, 'The Variables of contract has been frozen');
		_;
	}

	modifier frozen() {
		require(freezeVariable, 'The contract variables have not been frozen');
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
	) ERC721(name_, symbol_) OlympiansWhitelist(signerAddress_) {
		recalculateVariables();
	}

	function setPresaleInitializedAt(uint256 presaleInitializedAt_) external onlyOwner {
		presaleInitializedAt = presaleInitializedAt_;
	}

	function setPresaleFinishAt(uint256 presaleFinishAt_) external onlyOwner {
		require(
			presaleFinishAt_ >= presaleInitializedAt,
			'The pre sale FinishAt must be greater or equals to pre sale Initialized'
		);

		presaleFinishAt = presaleFinishAt_;
	}

	function setTreasury(IOlympiansTreasury olympiansTreasury_) external onlyOwner {
		emit SetTreasury(address(OlympiansTreasury = olympiansTreasury_));
	}

	function withdraw() external onlyOwner {
		payable(msg.sender).transfer(address(this).balance);
		emit Withdraw(msg.sender, address(this).balance);
	}

	function setBaseURI(string memory nftURI_) external onlyOwner {
		_nftURI = nftURI_;
		emit SetBaseURI(nftURI_);
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
	function mint(bytes32 nftType_) external payable definedTreasury frozen {
		require(nftType_ == GODS_TYPE || nftType_ == DEMIGODS_TYPE, 'type not allowed');
		require(block.timestamp >= presaleFinishAt, 'Sale has not yet started');

		uint256 _tokenId = ++_tokenIdCounter;
		require(_tokenId <= MAX_SUPPLY, 'Fulfilled supply');

		(uint256 _price, uint256 _percentage) = calculatePriceAndPercentage(nftType_, false);

		require(_price > 0 && msg.value == _price, 'Incorrent value');

		_safeMint(msg.sender, _tokenId);
		OlympiansTreasury.setNFTPercentage(_tokenId, _percentage);
	}

	/**
	 * @dev Mints NFT with type `nftType_` and transfers it to `msg.sender`
	 * @param nftType_ Type of NFT to be minted
	 * @param signature_ Sign to verify if you are authorized to mint
	 **/
	function mintPresale(
		bytes32 nftType_,
		bytes memory signature_
	) external payable definedTreasury frozen {
		require(nftType_ == GODS_TYPE || nftType_ == DEMIGODS_TYPE, 'type not allowed');
		require(block.timestamp <= presaleFinishAt, 'The pre-sale has already finished');
		require(block.timestamp >= presaleInitializedAt, 'The pre-sale has not yet started');

		require(verifyMinterSigner(nftType_, signature_), 'SIGNATURE_VALIDATION_FAILED');

		uint256 _tokenId = ++_tokenIdCounter;

		require(_tokenId <= MAX_SUPPLY, 'Fulfilled supply');

		(uint256 _price, uint256 _percentage) = calculatePriceAndPercentage(nftType_, true);

		require(_price > 0 && msg.value == _price, 'Incorrent value');

		_safeMint(msg.sender, _tokenId);
		OlympiansTreasury.setNFTPercentage(_tokenId, _percentage);
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

	function frozenVariables() external onlyOwner freezable {
		freezeVariable = true;
		emit FrozenVariables();
	}

	function setMaxSupply(
		uint256 maxSupply,
		uint256 maxSupplyGods
	) external freezable onlyOwner {
		require(
			maxSupply >= maxSupplyGods,
			'The maxSupply must be great or equals to maxSupplyGods'
		);
		MAX_SUPPLY = maxSupply;
		MAX_SUPPLY_GODS = maxSupplyGods;

		recalculateVariables();

		emit SetMaxSupply(maxSupply, maxSupplyGods);
	}

	function setPercentageNFTGods(
		uint256 percetangePerNFTGods
	) external freezable onlyOwner {
		PERCENTAGE_PER_NFT_GODS = percetangePerNFTGods;

		recalculateVariables();

		emit SetPercentageNFTGods(
			PERCENTAGE_PER_NFT_GODS,
			PERCENTAGE_PER_NFT_DEMIGODS,
			EARNING_PERCENTAGE_PER_GOD,
			EARNING_PERCENTAGE_PER_DEMIGOD
		);
	}

	function setPriceNFTGods(uint256 newPrice) external onlyOwner freezable {
		PRICE_PER_NFT_GODS = newPrice;

		emit SetPriceNFTGods(newPrice);
	}
	function setPriceNFTGodsPresale(uint256 newPrice) external onlyOwner freezable {
		PRICE_PER_NFT_GODS_PRESALE = newPrice;

		emit SetPriceNFTGodsPresale(newPrice);
	}
	function setPriceNFTDemigods(uint256 newPrice) external onlyOwner freezable {
		PRICE_PER_NFT_DEMIGODS = newPrice;

		emit SetPriceNFTDemigods(newPrice);
	}
	function setPriceNFTDemigodsPresale(uint256 newPrice) external onlyOwner freezable {
		PRICE_PER_NFT_DEMIGODS_PRESALE = newPrice;

		emit SetPriceNFTDemigodsPresale(newPrice);
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

			_price = isPresale_ ? PRICE_PER_NFT_GODS_PRESALE : PRICE_PER_NFT_GODS;
			_percentage = EARNING_PERCENTAGE_PER_GOD;
		}

		if (nftType_ == DEMIGODS_TYPE) {
			_demigodsCounter++;
			require(_demigodsCounter <= MAX_SUPPLY_DEMIGODS, 'Fulfilled Demigods-type supply');

			_price = isPresale_ ? PRICE_PER_NFT_DEMIGODS_PRESALE : PRICE_PER_NFT_DEMIGODS;
			_percentage = EARNING_PERCENTAGE_PER_DEMIGOD;
		}
	}

	function recalculateVariables() internal {
		if (MAX_SUPPLY_DEMIGODS != MAX_SUPPLY - MAX_SUPPLY_GODS)
			MAX_SUPPLY_DEMIGODS = MAX_SUPPLY - MAX_SUPPLY_GODS;

		if (PERCENTAGE_PER_NFT_DEMIGODS != PERCENTAGE_DENOMINATOR - PERCENTAGE_PER_NFT_GODS)
			PERCENTAGE_PER_NFT_DEMIGODS = PERCENTAGE_DENOMINATOR - PERCENTAGE_PER_NFT_GODS;

		if (
			MAX_SUPPLY_GODS > 0 &&
			EARNING_PERCENTAGE_PER_GOD != PERCENTAGE_PER_NFT_GODS / MAX_SUPPLY_GODS
		) EARNING_PERCENTAGE_PER_GOD = PERCENTAGE_PER_NFT_GODS / MAX_SUPPLY_GODS;

		if (
			MAX_SUPPLY_DEMIGODS > 0 &&
			EARNING_PERCENTAGE_PER_DEMIGOD != PERCENTAGE_PER_NFT_DEMIGODS / MAX_SUPPLY_DEMIGODS
		) EARNING_PERCENTAGE_PER_DEMIGOD = PERCENTAGE_PER_NFT_DEMIGODS / MAX_SUPPLY_DEMIGODS;
	}
}
