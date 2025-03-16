### Improved System Design: Paying Gas on Chain A Using a Stablecoin (e.g., USDC) from Chain B

Using the information provided in the **Gas Service Contract** document, we can refine and enhance the system design to ensure it aligns with Axelar's gas estimation and payment mechanisms. Below is the improved version of the system design.

---

### **1. High-Level Overview**
The goal remains the same: allow users to pay gas fees on **Chain A** using USDC from **Chain B**. However, we now incorporate Axelar's **Gas Service Contract** and its methods for accurate gas estimation, payment, and execution.

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
- **`calculateL1FeeForDestL2`**: If **Chain A** is an L2 chain, estimate the additional cost of posting the executed transaction back to the L1 chain.

#### **c. Smart Contracts**
- **AxelarGasService Contract**: Handles gas payments on the source chain (**Chain B**) and ensures the transaction is executed on the destination chain (**Chain A**).
- **Bridge Contract on Chain B**: Locks USDC and initiates the cross-chain transfer.
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
    "aUSDC" // sourceChainTokenSymbol,
    executeData: "0x..." // Optional: Required for L2 chains
  );
  console.log("Estimated Gas Fee:", gasFee);
  ```

  **Key Enhancements**:
  - Include the `executeData` parameter if **Chain A** is an L2 chain to account for the additional cost of posting the transaction back to the L1 chain.
  - Use the `gasMultiplier` parameter to add a buffer (e.g., 1.1x) to handle gas price volatility.

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

#### **Step 5: Pay Gas Fee on Chain A**
- The Axelar network mints a wrapped version of USDC on **Chain A** and sends it to the user's address.
- The user pays the gas fee on **Chain A** using the AxelarGasService contract:
  ```javascript
  const payGasTx = await gasReceiverContract.payNativeGasForContractCallWithToken(
    address(this), // Source contract address
    "avalanche", // Destination chain
    destinationContractAddress, // Address of the contract on Chain A
    payload, // Data payload for the transaction
    "wrappedUSDC", // Token symbol
    gasFeeInUnits, // Amount of wrapped USDC
    { value: gasFeeInUnits } // Gas payment
  );
  await payGasTx.wait();
  ```

---

### **4. Example Code**
Below is the improved example code incorporating the **Gas Service Contract**:

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
    "aUSDC", // sourceChainTokenSymbol
    "0x..." // executeData (Required for L2 chains)
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
  const payGasTx = await gasReceiverContract.payNativeGasForContractCallWithToken(
    address(this), // Source contract address
    "avalanche", // Destination chain
    destinationContractAddress, // Address of the contract on Chain A
    payload, // Data payload for the transaction
    "wrappedUSDC", // Token symbol
    gasFee, // Amount of wrapped USDC
    { value: gasFee } // Gas payment
  );
  await payGasTx.wait();

  console.log("Gas payment successful!");
}

payGasWithUSDC().catch(console.error);
```

---

### **5. Key Enhancements**
#### **a. Accurate Gas Estimation**
- Use the `gasLimit` parameter to avoid underestimation and ensure sufficient gas for execution.
- Include the `minGasPrice` parameter to handle volatile gas prices on the destination chain.
- For L2 chains, use the `executeData` parameter to estimate the additional cost of posting the transaction back to the L1 chain.

#### **b. Gas Payment Mechanism**
- Use the `payNativeGasForContractCallWithToken` method of the **AxelarGasService** contract to pay gas fees in the native token of the source chain.
- Ensure refunds are handled automatically by the Gas Service for unused gas.

#### **c. Handling Stuck Transactions**
- Monitor transactions on **Axelarscan** to identify and resolve stuck transactions.
- Add gas to stalled transactions using the AxelarJS SDK or manually execute the transaction on the destination chain.

#### **d. Round-Trip Transactions**
- Use `estimateGasFee` twice to calculate the total cost of a round-trip transaction (e.g., from **Chain A** to **Chain B** and back to **Chain A**).

---

### **6. Conclusion**
This improved design leverages Axelar's **Gas Service Contract** and SDK to provide a robust and efficient solution for paying gas fees on one chain using assets from another chain. By incorporating accurate gas estimation, handling volatile gas prices, and addressing potential issues like stuck transactions, this system ensures a seamless user experience for cross-chain gas payments.