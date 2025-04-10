# Axelar Cross-Chain Gas Payment System

## Overview
The goal of this system is to allow users to pay gas fees on one blockchain (e.g. Ethereum) using tokens from another blockchain (e.g. Avalanche). This solution leverages Axelar's interoperability framework, enabling secure and seamless communication between blockchains. The design prioritizes modularity, scalability, and developer-friendliness while ensuring security and usability.

---

## Problem Statement

### Why Do Users Need Native Gas Tokens on Every Chain?
Users interacting with decentralized applications (dApps) across multiple blockchains must hold the native gas token of each blockchain they engage with (e.g. ETH for Ethereum, MATIC for Polygon, AVAX for Avalanche). Without these tokens, users cannot execute transactions or interact with smart contracts.

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

## System Design - Key Components

### User Interaction
1. The user specifies the amount of gas they want to pay on Chain A and selects a stablecoin (e.g. USDC) from Chain B as payment in one transaction.

### Axelar General Message Passing (GMP)
Axelar’s General Message Passing (GMP) enables developers building on one chain to call any function on any other connected chain.  
With GMP, you can:
- Call a contract on Chain B from Chain A.
- Call a contract on Chain B from Chain A and attach some tokens.

### Axelar Executable
The Axelar Executable is a component of the Axelar General Message Passing (GMP) flow, allowing the execution of custom logic in response to messages from different blockchains.  
By inheriting from the Axelar Executable, your contract can process and respond to incoming cross-chain GMP data.

### Gas Service and Transaction Pricing
Transactions using Axelar often have costs associated with the source chain, the Axelar network, and the destination chain.  
Whether for token transfers or General Message Passing (GMP), every cross-chain transaction consists of four types of costs:
1. Initiating the transaction on the source chain.
2. Processing the transaction through the Axelar blockchain.
3. Relaying to the gateway contract on the destination chain.
4. Executing the destination smart contract with the payload.

To simplify paying for transaction pricing through the pipeline, Axelar offers two general solutions:
- For token transfers, a fixed “relayer fee” is deducted from the amount of assets being transferred cross-chain.
- For General Message Passing (`callContract` and `callContractWithToken`), a chain-agnostic gas-relaying service is implemented to accept gas payments from users on the source chain in its native currency.

### Interchain Token Transfers
The Interchain Token Service (ITS) allows ERC-20 tokens to be available on multiple blockchains. It preserves native token qualities while enabling easy management of token features and supply. The interchainTransfer()` function sends a cross-chain transfer via the Interchain Token Service.
Interchain Tokens run on open-source code via smart contracts on a public blockchain secured by a dynamic validator set. With ITS, you can have multiple blockchains with canonical versions of your token that all share a single EVM address.  
You can either create new Interchain Tokens from scratch or update tokens that already exist on a supported blockchain.

### EVM Relayer
The Axelar EVM relayer facilitates communication between different EVM-compatible chains on the Axelar network. Both legacy and EIP-1559 transaction types are supported.  
Each chain has a relayer queue that receives transaction data. These queues serve as the relayer’s entry point. The Axelar network has multiple instances of the EVM relayer service running in parallel, waiting to pick up and process messages.  
This way, multiple transactions can be executed simultaneously. If a process unexpectedly stops or gets killed in the middle of a relay, an internal database will recover the payload, and the transaction will be retried when the process resumes.

The relayer follows three basic steps:
1. Receive payloads, which must contain the destination address (to), payload value (value), and transaction data (data).
2. Query the appropriate gas fee and price for the payload and create a transaction with those values.
3. Broadcast the transaction.

---

## How Axelar Enables This System

### General Message Passing (GMP)
Axelar’s GMP enables secure communication between blockchains. In this system:
A call to Chain B from Chain A and sending tokens along the way requires calling `callContractWithToken` on the gateway of Chain A.  
The `callContractWithToken` function call includes:
1. The destination chain.
2. The destination contract address, which must inherit from `AxelarExecutableWithToken` defined in `AxelarExecutableWithToken.sol`.
3. The payload bytes to pass to the destination contract.
4. The symbol of the token to transfer, which must be a supported (Interchain Token Service) asset.
5. The amount of the token to transfer.

### Cross-Chain Process

**Setup**
1. The destination application contract implements the `AxelarExecutable.sol` to receive the cross-chain message.
2. The destination application contract stores the address of the local Gateway contract.

**Steps**
 **At the source chain (Chain B)**:
  1. Call the `callContract` (or `callContractWithToken`) function on the Axelar Gateway contract to initiate a call. Once the call is initiated, the user can track its status at [https://axelarscan.io/gmp/[txHash]](https://axelarscan.io/gmp/[txHash]) or programmatically via the AxelarJS SDK.
  2. Prepay the gas for the decentralized Axelar consensus and the necessary transactions to approve and execute on the destination chain.
  3. The call enters the Axelar Gateway from the source chain.

  **On Axelar Network**
  1. A relayer monitors the `ContractCall` event and submits a transaction to the Axelar network to request validation. The relayer also stores the payload in a database, keyed by hash(payload) for later retrieval.
  2. Axelar validators then vote on-chain to validate the ContractCall event content.
  3. A relayer requests the Axelar network to prepare a command batch, including the pending payload approval (potentially batched with other messages), and requests validator signatures.
  4. A signed batch of approved payloads is prepared on Axelar that anyone can view.
  5. The Axelar network confirms the call and utilizes funds from the source chain’s native (USDC ERC-20) token reserves to cover the gas costs on both the Axelar blockchain and the destination chain (Chain A).

- **At the destination chain (Chain A)**:
  1. A relayer submits the signed batch to the destination gateway contract, which records the approval of the payload hash and emits a `ContractCallApproved` event.
  2. A trustless relayer service (can be anyone) listens for this event and calls IAxelarExecutable.execute() on the destination contract with the payload and other data as params.
  3. If the paid gas is insufficient to approve or execute on the destination chain, Axelar offers monitoring and recovery steps to handle such scenarios.
  4. The execute method on the destination contract verifies the call was indeed approved by Axelar validators by calling `validateContractCall()` from the AxelarExecutable where it’s defined on its Axelar gateway contract.
  5. The gateway records that the destination application contract validated the approval and did not allow `validateContractCall` to be called again (to prevent replay of execute).
  6. The destination application contract uses the payload to `_execute` its logic.

### Estimate and Pay Gas
Gas estimation is the process of estimating the gas required to execute a transaction—specifically, a multichain transaction with Axelar. An application that wants Axelar to automatically execute contract calls on the destination chain must do the following:
1. Set up the `AxelarQueryAPI` with environment-specific configurations, ensuring accurate communication with Axelar’s network services. This API dynamically computes the necessary fees for a multichain transaction on the Axelar network.
2. Estimate the `gasLimit` that the contract call will require in the executable contract on the destination chain.
3. Fetch the gas fees for a transaction:
   - Chain- and asset-specific fees: The API retrieves fee information for particular chains and assets, enabling precise fee estimations necessary for transaction executions.
   - Transfer fees: For transactions involving asset transfers, the API calculates fees based on source and destination chain details, the assets involved, and the transfer amount.
   - If the destination chain is an EVM L2 chain, it will incur an extra cost for posting the executed transaction back to the L1 chain. The API estimates these extra fees with methods such as `calculateL1FeeForDestL2()`.
   - `estimateGasFee()` will estimate the fee (including any additional fees for L2 chains) in the destination token, convert it to the same price in the source token, and return the converted amount.
4. Pay the `AxelarGasService` smart contract on the source chain with `payNativeGasForContractCall()` or `payNativeGasForContractCallWithToken()`. Gas fees are paid in the native token of the source chain.

### Interchain Token Transfers
Axelar’s token transfer capabilities enable seamless bridging of USDC from Chain B to Chain A. Interchain Tokens are tokens deployed via the Interchain Token Service (ITS).  
These tokens are relatively simple ERC-20 contracts with built-in ITS integration, making them bridgeable to other blockchains as soon as they are deployed. You can initiate an interchain transfer from your source chain to a destination chain by using the `interchainTransfer` method on the ITS contract.

**Canonical Interchain Token**
An Interchain Token is an ERC-20 token that can be transferred between blockchains, preserving native token qualities. At the core, an Interchain Token is an ERC-20 contract on a public blockchain secured by a dynamic validator set.
A canonical Interchain Token is a token originally deployed on one chain that now has interchain capabilities through ITS. The Interchain Token Service wraps the token on the original chain to give it these capabilities, then duplicates the wrapped original on all other chains. This standardization ensures consistent behavior and enables interoperability between blockchains, allowing cross-chain transactions and interactions within blockchain networks that support various chains.

**Token Managers**  
Token Managers are contracts that facilitate the connection between your interchain token and the Interchain Token Service (ITS). For certain manager types, such as mint/burn Token Manager, the manager is the `msg.sender` of the transaction being executed on the destination chain for the token when it is bridged in.

**Mint/Burn**  
Minting refers to the creation of new tokens, typically increasing the total supply. Burning involves permanently removing tokens from circulation, reducing the total supply. In the Interchain Token Service, the contract’s Token Manager will mint new tokens on its chain when there are incoming token transfers, and burn the received tokens when there are outgoing token transfers.

---

## Key Challenge & Solution

### Challenge: Transaction Latency
Cross-chain operations introduce delays due to block confirmation times, message relaying, and token swaps. This latency could frustrate users expecting near-instantaneous gas payments.

### Solution: Gateway Tokens
Gateway tokens are a collection of well-known ERC-20 tokens (such as USDC) that have been wrapped by the Interop Labs team to provide easy cross-chain liquidity between blockchains.

---

## Smart Contract Example & Deployment Details

**Function Names :**
+ The `callContractWithToken` function is used to initiate the cross-chain transfer.
+ The payGasForContractCallWithToken function handles gas payments for the transaction.

**Event Emission :**
+ The GasPaidForContractCallWithToken event is emitted when gas is paid for the transaction.

**Payload Handling :**
+ The payload contains the encoded destination address, which is decoded in the _execute function on the destination chain.

**Gas Payment :**
+ The payNativeGasForContractCallWithToken function ensures that the gas fees are paid using native tokens (AVAX).


Avalanche Testnet (Chain A):
    - Gateway Address : 0xC249632c2D40b9001FE907806902f63038B737Ab
    - Gas Service Address : 0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6

BNB Testnet (Chain B):
    - Gateway Address : 0x4D147dCb984e6affEEC47e44293DA442580A3Ec0
    - Gas Service Address : 0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6

Deploy the contract on both chains with the respective gateway and gas service addresses.

Example Usage
1. Deploy the contract on Avalanche Testnet:
```javascript 
npx hardhat deploy --network avalanche-testnet --constructor-args <gateway-address> <gas-service-address>
```
2. Send USDC from Avalanche Testnet to BNB Testnet:
```javascript
contract.callContractWithToken{value: gasFee}(
    "binance",
    "0xRecipientOnBNB",
    abi.encode("0xRecipientOnBNB"),
    "USDC",
    100e6
);
```
Below is a Solidity contract snippet that demonstrates how to process a gas payment request using Axelar GMP.
See ```code_snippet.sol```

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
   - Security measures like reentrancy guards and detailed error handling are omitted for simplicity.
   - Pre-funding mechanisms and advanced fee estimation are not included in this minimal example.

---

## Conclusion
This document outlines a modular and scalable system for enabling cross-chain gas payments using Axelar’s interoperability framework. By leveraging GMP and Interchain Token Transfers, the system abstracts the need for users to hold native gas tokens on every blockchain they interact with. While challenges like transaction latency exist, solutions such as pre-funding mechanisms can mitigate these issues effectively.

---

