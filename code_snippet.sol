// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { AxelarExecutable } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol';
import { IAxelarGasService } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol';
import { IERC20 } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IERC20.sol';
import { SafeTokenTransfer, SafeTokenTransferFrom } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/libs/SafeTransfer.sol';
import { IAxelarGateway } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol';

contract USDCInterchainTransfer is AxelarExecutable {
    // Address of the USDC token on Avalanche Testnet
    address public constant USDC_AVAX_TESTNET = 0x204eEf60d7158653013158Bc1283860124249805;
    IERC20 public immutable usdc;

    // Address of the Axelar Gas Service
    IAxelarGasService public immutable gasService;

    // Events
    event USDCSent(string destinationChain, string destinationAddress, uint256 amount);
    event USDCTransferred(address indexed sender, uint256 amount);

    /**
     * @notice Constructor to initialize the contract
     * @param _gateway Address of the Axelar Gateway on the deployed chain
     * @param _gasReceiver Address of the Axelar Gas Service on the deployed chain
     */
    constructor(address _gateway, address _gasReceiver) AxelarExecutable(_gateway) {
        gasService = IAxelarGasService(_gasReceiver);
        usdc = IERC20(USDC_AVAX_TESTNET);
    }

    /**
     * @notice Sends USDC from Avalanche Testnet to BNB Testnet
     * @param destinationChain Name of the destination chain (e.g., "binance")
     * @param destinationAddress Address on the destination chain to receive the USDC
     * @param amount Amount of USDC to transfer
     */
    function callContractWithToken(
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        string calldata symbol,
        uint256 amount
    ) external payable override {
        require(amount > 0, "Amount must be greater than zero");

        // Transfer USDC from the sender to this contract
        SafeTokenTransferFrom.safeTransferFrom(usdc, msg.sender, address(this), amount);

        // Approve the Axelar Gateway to spend the USDC
        SafeTokenTransfer.safeApprove(usdc, address(gateway()), amount);

        // Pay for the gas required for the cross-chain transfer
        gasService.payNativeGasForContractCallWithToken{value: msg.value}(
            address(this),
            destinationChain,
            destinationAddress,
            payload,
            symbol,
            amount,
            msg.sender
        );

        // Initiate the cross-chain transfer
        gateway().callContractWithToken(destinationChain, destinationAddress, payload, symbol, amount);

        emit USDCSent(destinationChain, destinationAddress, amount);
        emit USDCTransferred(msg.sender, amount);
    }

    /**
     * @notice Pays gas for a contract call with a token
     * @param sender Sender address
     * @param destinationChain Name of the destination chain
     * @param destinationAddress Address on the destination chain
     * @param payload Encoded payload
     * @param symbol Token symbol (e.g., "USDC")
     * @param amount Token amount to transfer
     * @param gasToken Address of the gas token
     * @param gasFeeAmount Amount of gas fee
     * @param refundAddress Address to refund leftover gas
     */
    function payGasForContractCallWithToken(
        address sender,
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        string memory symbol,
        uint256 amount,
        address gasToken,
        uint256 gasFeeAmount,
        address refundAddress
    ) external override {
        emit GasPaidForContractCallWithToken(
            sender,
            destinationChain,
            destinationAddress,
            keccak256(payload),
            symbol,
            amount,
            gasToken,
            gasFeeAmount,
            refundAddress
        );

        // Transfer the gas fee from the sender to this contract
        IERC20(gasToken).safeTransferFrom(sender, address(this), gasFeeAmount);
    }

    /**
     * @notice Executes the logic on the destination chain
     * @param commandId Unique identifier for the command
     * @param sourceChain Name of the source chain
     * @param sourceAddress Address of the sender on the source chain
     * @param payload Encoded data containing the destination address
     */
    function _execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) internal override {
        // Decode the payload to get the destination address
        string memory destinationAddress = abi.decode(payload, (string));

        // Mint or transfer the USDC to the recipient on the destination chain
        uint256 amount = gateway().tokenBalance("USDC", address(this));
        SafeTokenTransfer.safeTransfer(usdc, destinationAddress, amount);

        emit USDCTransferred(sourceAddress, amount);
    }
}