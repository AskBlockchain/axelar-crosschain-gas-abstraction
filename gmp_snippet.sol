// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol";

contract CrossChainGasPayment {
    IAxelarGateway public gateway;
    IAxelarGasService public gasService;

    constructor(address _gateway, address _gasService) {
        gateway = IAxelarGateway(_gateway);
        gasService = IAxelarGasService(_gasService);
    }

    function payGasOnAnotherChain(
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        string calldata gasToken,
        uint256 gasAmount
    ) external payable {
        // Pay gas fees using Axelar Gas Service
        gasService.payNativeGasForContractCall{value: msg.value}(
            address(this),
            destinationChain,
            destinationAddress,
            payload,
            msg.sender
        );

        // Send the payload to the destination chain
        gateway.callContract(destinationChain, destinationAddress, payload);
    }
}