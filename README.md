# ScholarChain Smart Contract

## Description
**ScholarChain** is an Ethereum-based smart contract designed to manage the decentralized publication of scientific articles using blockchain technology. This contract provides features for both authors and publishers, including article submission, publisher decisions, publication fee payments, and the creation of Non-Fungible Tokens (NFTs) as digital certificates for the published articles.

The main functions of this contract include:
- **Create Submission**: Authors submit articles along with publication fees.
- **Publisher Decision**: Publishers set the status of the article (review, accepted, or rejected).
- **Finalize and Mint**: Once accepted, the publisher uploads the DOI and CID to IPFS and mints an NFT for the author.
- **Refund Mechanism**: If the article is rejected or there are issues with the publisher, funds can be refunded to the author.

This contract aims to enhance transparency and credibility in scientific publishing and to create a more decentralized system in academia.

## Features
- **ERC721**: Minting NFTs for scientific articles.
- **ERC20**: Payment using the IDRX token.
- **Escrow System**: Managing publication fee payments.
- **Fee System**: Handling publication and refund fees.
- **Reviewer Fee**: Payment to reviewers if the article is reviewed.

## Key Features
1. **Create Submission**: 
   - Authors can submit their articles along with the publication fee.
2. **Publisher Decision**:
   - Publishers can decide whether an article is accepted, rejected, or under review.
3. **Finalize and Mint**:
   - Once an article is accepted, the publisher uploads the DOI and CID to IPFS and mints an NFT for the author.
4. **Refund**:
   - Refund system for articles that are rejected or if the publisher is inactive.

## Technologies Used
- **Solidity**: Programming language for writing smart contracts.
- **OpenZeppelin Contracts**: Standard library for ERC721 and ERC20 smart contracts.
