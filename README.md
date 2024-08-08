# Olympex Smart Contracts Repository

## Introduction

Welcome to the Smart Contracts Audit Repository by **Olympex**. This repository contains a set of smart contracts developed by our team.

## Contracts

This repository includes the following smart contracts:

1. **OlympexAggregator.sol**
   - **Description:** Main contract for token swapping, verifying execution requirements and calling the Messenger contract to route through multiple liquidity pools using encoded parameters.

2. **OlympexMessenger.sol**
   - **Description:** Executes calls to various modules and contracts, transferring funds across protocols and pools to complete the swap and distribute fees.

3. **FeeCollector.sol**
    - **Description:** Stores the collected fees, acting as the central repository for the protocol's treasury.

4. **OlympiansTreasury.sol**
   - **Description:** Serves as the central repository for funds related to Investment NFTs, managing and allocating collected dividends and assets.

5. **OlympexLimitOrder.sol**
   - **Description:** Executes limit orders within the protocol. This contract call to OlympexAggregator contract for make the swaps.

6. **OlympexPas.sol**
   - **Description:** Utility NFT: Manages the minting and utility aspects of this NFT, providing holders with access to specific benefits within the protocol.

7. **Olympians.sol**
   - **Description:** Investment NFT: Manages the minting and utility aspects of this NFT, providing holders with access to dividens of the fee collected.


## Purpose

The primary goal of this repository is to facilitate the auditing process. By providing open access to our smart contracts, we invite auditors to review and provide feedback on their security and performance. This proactive approach is part of our commitment to transparency and quality.

## About Olympex

**Olympex** is a leading innovator in the blockchain space, dedicated to developing secure, efficient, and impactful solutions. Our team of experts works tirelessly to ensure that our products meet the highest standards of excellence and security.

## Get in Touch

If you have any questions or need further information, please feel free to contact us:

- **Email:** [info@olympex.io](mailto:info@olympex.io)
- **Website:** [www.olympex.io](https://www.olympex.io)
- **Twitter:** [@olympex](https://twitter.com/olympex)
- **LinkedIn:** [Olympex](https://www.linkedin.com/company/olympex)

We look forward to collaborating with you and ensuring the success of our smart contracts.