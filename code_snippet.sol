// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { AxelarExecutable } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol';
import { IAxelarGasService } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol';
import { IERC20 } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IERC20.sol';
import { SafeTokenTransfer, SafeTokenTransferFrom } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/libs/SafeTransfer.sol';

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
    function sendUSDC(
        string calldata destinationChain,
        string calldata destinationAddress,
        uint256 amount
    ) external payable {
        require(amount > 0, "Amount must be greater than zero");

        // Transfer USDC from the sender to this contract
        SafeTokenTransferFrom.safeTransferFrom(usdc, msg.sender, address(this), amount);

        // Approve the Axelar Gateway to spend the USDC
        SafeTokenTransfer.safeApprove(usdc, address(gateway()), amount);

        // Estimate and pay for the gas required for the cross-chain transfer
        bytes memory payload = abi.encode(destinationAddress);
        gasService.payNativeGasForContractCallWithToken{value: msg.value}(
            address(this),
            destinationChain,
            destinationAddress,
            payload,
            "USDC",
            amount,
            msg.sender
        );

        // Initiate the cross-chain transfer
        gateway().callContractWithToken(destinationChain, destinationAddress, payload, "USDC", amount);

        emit USDCSent(destinationChain, destinationAddress, amount);
        emit USDCTransferred(msg.sender, amount);
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
        // This assumes the destination chain has a corresponding USDC contract
        // and the Axelar Gateway handles the minting process.
        uint256 amount = gateway().tokenBalance("USDC", address(this));
        SafeTokenTransfer.safeTransfer(usdc, destinationAddress, amount);

        emit USDCTransferred(sourceAddress, amount);
    }
}