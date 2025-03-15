### System Design: Paying Gas on Chain A Using a Stablecoin (e.g., USDC) from Chain B

The goal is to design a system where users can pay gas fees on **Chain A** using a stablecoin (e.g., USDC) from **Chain B**. This involves leveraging the Axelar network and its services to facilitate cross-chain communication and asset transfers. Below is a simple, step-by-step design for this system.

---

### **1. High-Level Overview**
- **User Interaction**: The user initiates a transaction on **Chain A**, specifying that they want to pay gas fees using USDC from **Chain B**.
- **Axelar Network**: The Axelar network facilitates:
  - Cross-chain communication between **Chain A** and **Chain B**.
  - Token bridging (USDC from **Chain B** to **Chain A**).
  - Gas estimation and payment abstraction.
- **Gas Payment Flow**:
  1. The user approves the Axelar bridge contract on **Chain B** to transfer USDC.
  2. The Axelar network locks the USDC on **Chain B** and mints a wrapped version of USDC on **Chain A**.
  3. The wrapped USDC is used to pay gas fees on **Chain A**.
  4. The Axelar network ensures the transaction completes successfully on **Chain A**.

---

### **2. Components Involved**
#### **a. AxelarJS SDK**
- Install the AxelarJS SDK:
  ```bash
  npm i @axelar-network/axelarjs-sdk
  ```
- Instantiate the `AxelarQueryAPI` module:
  ```javascript
  const sdk = new AxelarQueryAPI({
    environment: "testnet", // or "mainnet"
  });
  ```

#### **b. Key Queries**
- **`estimateGasFee`**: Estimate the gas fee required for the transaction on **Chain A**.
- **`getTransferFee`**: Calculate the base fee for transferring USDC from **Chain B** to **Chain A**.
- **`getDenomFromSymbol`**: Convert the USDC symbol (`aUSDC`) to its underlying denom (`uausdc`).

#### **c. Smart Contracts**
- **Bridge Contract on Chain B**: Handles locking USDC and initiating the cross-chain transfer.
- **Gas Receiver Contract on Chain A**: Accepts the wrapped USDC and uses it to pay gas fees.

---

### **3. Workflow**
#### **Step 1: User Initiates Transaction**
- The user specifies:
  - Source chain (**Chain B**): Where USDC resides.
  - Destination chain (**Chain A**): Where the gas fee is paid.
  - Amount of USDC to use for gas payment.

#### **Step 2: Estimate Gas Fee**
- Use the `estimateGasFee` method to calculate the gas fee on **Chain A**:
  ```javascript
  const gasFee = await sdk.estimateGasFee(
    "ethereum", // sourceChainId (Chain B)
    "avalanche", // destinationChainId (Chain A)
    "200000", // gasLimit
    "auto", // gasMultiplier
    "aUSDC" // sourceChainTokenSymbol
  );
  console.log("Estimated Gas Fee:", gasFee);
  ```

#### **Step 3: Approve USDC Transfer**
- The user approves the Axelar bridge contract on **Chain B** to transfer the required amount of USDC:
  ```javascript
  const approveTx = await usdcContract.approve(
    axelarBridgeAddress,
    gasFeeInUnits
  );
  await approveTx.wait();
  ```

#### **Step 4: Lock USDC and Initiate Transfer**
- The user calls the Axelar bridge contract on **Chain B** to lock USDC and initiate the cross-chain transfer:
  ```javascript
  const transferTx = await axelarBridge.lockTokens(
    "avalanche", // destinationChainId
    userAddressOnChainA, // recipient address on Chain A
    "aUSDC", // token symbol
    gasFeeInUnits // amount of USDC to transfer
  );
  await transferTx.wait();
  ```

#### **Step 5: Mint Wrapped USDC on Chain A**
- The Axelar network mints a wrapped version of USDC on **Chain A** and sends it to the user's address.

#### **Step 6: Pay Gas Fee on Chain A**
- The user uses the wrapped USDC to pay the gas fee on **Chain A**:
  ```javascript
  const payGasTx = await gasReceiverContract.payGasWithToken(
    "wrappedUSDC", // token symbol
    gasFeeInUnits // amount of wrapped USDC
  );
  await payGasTx.wait();
  ```

---

### **4. Example Code**
Below is a simplified example of the entire flow:

```javascript
const { AxelarQueryAPI } = require("@axelar-network/axelarjs-sdk");

// Initialize AxelarQueryAPI
const sdk = new AxelarQueryAPI({ environment: "testnet" });

async function payGasWithUSDC() {
  // Step 1: Estimate Gas Fee
  const gasFee = await sdk.estimateGasFee(
    "ethereum", // sourceChainId (Chain B)
    "avalanche", // destinationChainId (Chain A)
    "200000", // gasLimit
    "auto", // gasMultiplier
    "aUSDC" // sourceChainTokenSymbol
  );
  console.log("Estimated Gas Fee:", gasFee);

  // Step 2: Approve USDC Transfer
  const approveTx = await usdcContract.approve(axelarBridgeAddress, gasFee);
  await approveTx.wait();

  // Step 3: Lock USDC and Initiate Transfer
  const transferTx = await axelarBridge.lockTokens(
    "avalanche", // destinationChainId
    userAddressOnChainA, // recipient address on Chain A
    "aUSDC", // token symbol
    gasFee // amount of USDC to transfer
  );
  await transferTx.wait();

  // Step 4: Pay Gas Fee on Chain A
  const payGasTx = await gasReceiverContract.payGasWithToken(
    "wrappedUSDC", // token symbol
    gasFee // amount of wrapped USDC
  );
  await payGasTx.wait();

  console.log("Gas payment successful!");
}

payGasWithUSDC().catch(console.error);
```

---

### **5. Key Considerations**
- **Gas Multiplier**: Use a buffer (e.g., 1.1x) to account for potential slippage during execution.
- **L2 Chains**: If **Chain A** is an L2 chain, include the `executeData` parameter in `estimateGasFee` for accurate cost estimation.
- **Security**: Ensure proper validation of user inputs and smart contract interactions to prevent exploits.

---

### **6. Conclusion**
This design leverages the Axelar network to enable seamless cross-chain gas payments. By combining the AxelarJS SDK with smart contracts and token bridging, users can pay gas fees on one chain using assets from another chain. This approach enhances user experience and expands the utility of cross-chain applications.