# Cross-Chain Gas Payment System

## Overview

The goal of this system is to allow users to pay gas fees on one blockchain (e.g. Ethereum) using tokens from another blockchain (e.g. Avalanche). This solution leverages Axelar's interoperability framework, enabling secure and seamless communication between blockchains. The design prioritizes modularity, scalability, and developer-friendliness while ensuring security and usability.

---

## Problem Statement

### Why Do Users Need Native Gas Tokens on Every Chain?
Users interacting with decentralized applications (dApps) across multiple blockchains must hold the native gas token of each blockchain they engage with (e.g., ETH for Ethereum, MATIC for Polygon, AVAX for Avalanche). Without these tokens, users cannot execute transactions or interact with smart contracts.

### How Does This Impact User Experience?
1. **Friction**: Users need to acquire and manage multiple tokens, complicating their onboarding process.
2. **Fragmentation**: Holding multiple tokens increases cognitive load and exposes users to price volatility.
3. **Barriers to Entry**: New users unfamiliar with crypto may find navigating multiple chains and tokens daunting.

### What Current Solutions Exist, and What Are Their Limitations?
- **Bridges**: Allow users to transfer tokens between chains but still require holding native gas tokens for bridge transactions.
- **Meta-transactions**: Enable gasless transactions by having a relayer pay fees, but this introduces centralization risks and complexity.
- **Wrapped Tokens**: Provide liquidity but still necessitate native tokens for gas payments.

These solutions either fail to fully abstract gas fees or introduce additional complexity and risks.

---

## System Design

### User Interaction
1. The user specifies the amount of gas they want to pay on Chain A and selects a stablecoin (e.g. USDC) from Chain B as payment.
2. The system calculates the equivalent value in USDC based on real-time exchange rates.

### Axelar General Message Passing (GMP)
A cross-chain message is sent via Axelar GMP to relay the gas payment request from Chain B to Chain A. The message includes details such as the user’s address, the amount of USDC to be transferred, and the target gas fee.

### Interchain Token Transfers
Axelar bridges the USDC from Chain B to Chain A. On Chain A:
1. The bridged USDC is swapped for the native gas token (e.g., ETH) using a decentralized exchange (DEX) or liquidity pool.
2. The acquired native gas token is used to pay the gas fee on behalf of the user.
3. Any leftover tokens are refunded to the user’s wallet on Chain A.

---

## How Axelar Enables This System

### General Message Passing (GMP)
Axelar’s GMP enables secure communication between blockchains. In this system:
- It relays the gas payment request from Chain B to Chain A.
- The message contains details like the user’s address, the amount of USDC to be transferred, and the target gas fee.

### Interchain Token Transfers
Axelar’s token transfer capabilities enable seamless bridging of USDC from Chain B to Chain A. Once bridged, the tokens can be converted into the native gas token using a DEX or liquidity pool.

---

## Key Challenge & Solution

### Challenge: Transaction Latency
Cross-chain operations introduce delays due to block confirmation times, message relaying, and token swaps. This latency could frustrate users expecting near-instantaneous gas payments.

### Solution: Pre-Funding Mechanism
To mitigate latency, the system can implement a pre-funding mechanism:
1. Users lock a small amount of stablecoins (e.g., USDC) in a smart contract on Chain B.
2. These funds are bridged to Chain A in advance and held in a liquidity pool.
3. When the user requests gas payment, the system uses the pre-funded liquidity to pay the gas fee immediately, reducing perceived delays.

---

## Smart Contract Example (Minimal Version)

Below is a Solidity contract snippet that demonstrates how to process a gas payment request using Axelar GMP.

### Contract Code

```solidity
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { AxelarExecutable } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol';
import { IAxelarGateway } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol';
import { IERC20 } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IERC20.sol';
import { IAxelarGasService } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol';

/**
 * @title Cross-Chain Gas Payment
 * @notice Allows users to pay gas fees on one blockchain using tokens from another.
 */
contract CrossChainGasPayment is AxelarExecutable {
    IAxelarGasService public immutable gasService;

    event GasPaymentProcessed(address indexed user, uint256 amount);

    constructor(address _gateway, address _gasReceiver) AxelarExecutable(_gateway) {
        gasService = IAxelarGasService(_gasReceiver);
    }

    /**
     * @notice Initiates a cross-chain gas payment request.
     * @param destinationChain Name of the destination chain (e.g., "Ethereum").
     * @param destinationAddress Address on the destination chain where gas will be paid.
     * @param symbol Token symbol (e.g., "USDC") used for payment.
     * @param amount Amount of tokens to be sent for gas payment.
     */
    function payGasCrossChain(
        string memory destinationChain,
        string memory destinationAddress,
        string memory symbol,
        uint256 amount
    ) external payable {
        require(msg.value > 0, 'Gas payment in native token is required');

        // Fetch token address for the given symbol
        address tokenAddress = gateway.tokenAddresses(symbol);

        // Transfer tokens from the user to this contract
        IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);

        // Approve Axelar Gateway to spend the tokens
        IERC20(tokenAddress).approve(address(gateway), amount);

        // Pay for the cross-chain message execution using native gas
        gasService.payNativeGasForContractCallWithToken{ value: msg.value }(
            address(this),
            destinationChain,
            destinationAddress,
            abi.encode(msg.sender, amount), // Payload includes user address and amount
            symbol,
            amount,
            msg.sender
        );

        // Send the cross-chain message with tokens
        gateway.callContractWithToken(destinationChain, destinationAddress, abi.encode(msg.sender, amount), symbol, amount);

        emit GasPaymentProcessed(msg.sender, amount);
    }

    /**
     * @notice Executes the gas payment logic on the destination chain.
     * @dev Triggered automatically by Axelar relayers.
     * @param payload Encoded message containing user address and amount.
     * @param tokenSymbol Symbol of the token sent from the source chain.
     * @param amount Amount of tokens sent from the source chain.
     */
    function _executeWithToken(
        string calldata, // Source chain (not used here)
        string calldata, // Source address (not used here)
        bytes calldata payload,
        string calldata tokenSymbol,
        uint256 amount
    ) internal override {
        (address user, uint256 paymentAmount) = abi.decode(payload, (address, uint256));

        // Convert bridged tokens into the native gas token on the destination chain
        address tokenAddress = gateway.tokenAddresses(tokenSymbol);
        IERC20(tokenAddress).approve(address(someDEX), paymentAmount); // Approve DEX for swapping
        someDEX.swapTokensForNative(tokenAddress, paymentAmount); // Swap tokens for native gas

        // Use the acquired native gas to pay for the user's transaction
        // (Logic for paying gas can be implemented here)

        emit GasPaymentProcessed(user, paymentAmount);
    }
}
```

### Explanation of the Contract
1. **What the Contract Does**:
   - Users initiate a cross-chain gas payment by specifying the destination chain, destination address, token symbol, and amount.
   - The contract bridges the specified tokens to the destination chain using Axelar's Interchain Token Transfers.
   - On the destination chain, the bridged tokens are swapped for the native gas token via a DEX.
   - The acquired native gas token is then used to pay the gas fee on behalf of the user.

2. **How Axelar GMP Is Used**:
   - `callContractWithToken`: Sends a cross-chain message along with tokens from the source chain to the destination chain.
   - `payNativeGasForContractCallWithToken`: Pays for the execution of the cross-chain message using the native gas token of the source chain.
   - `_executeWithToken`: Automatically executed on the destination chain by Axelar relayers. It processes the incoming message and tokens, converting them into the native gas token for gas payment.

3. **Assumptions and Simplifications**:
   - A decentralized exchange (DEX) exists on the destination chain for swapping bridged tokens into the native gas token.
   - Security measures like reentrancy guards and detailed error handling are omitted for simplicity.
   - Pre-funding mechanisms and advanced fee estimation are not included in this minimal example.

---

## Conclusion

This document outlines a modular and scalable system for enabling cross-chain gas payments using Axelar’s interoperability framework. By leveraging GMP and Interchain Token Transfers, the system abstracts the need for users to hold native gas tokens on every blockchain they interact with. While challenges like transaction latency exist, solutions such as pre-funding mechanisms can mitigate these issues effectively.