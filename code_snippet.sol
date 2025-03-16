// SPDX-License-Identifier: MIT
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