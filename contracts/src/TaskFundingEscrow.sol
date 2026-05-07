// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AgentRegistry} from "./AgentRegistry.sol";
import {TaskAcceptanceRegistry} from "./TaskAcceptanceRegistry.sol";
import {TaskIntentMarket} from "./TaskIntentMarket.sol";

contract TaskFundingEscrow {
    enum EscrowStatus {
        None,
        Funded,
        Refunded,
        Released
    }

    struct EscrowRecord {
        address payer;
        uint256 amount;
        EscrowStatus status;
    }

    error InvalidAgentRegistry();
    error InvalidTaskIntentMarket();
    error InvalidTaskAcceptanceRegistry();
    error InvalidFundingAmount();
    error TaskNotOpen(uint256 taskId);
    error TaskNotAssigned(uint256 taskId);
    error TaskNotCancelled(uint256 taskId);
    error TaskResultNotAccepted(uint256 taskId);
    error NotTaskRequester(uint256 taskId, address caller);
    error NotEscrowPayer(uint256 taskId, address caller);
    error EscrowAlreadyFunded(uint256 taskId);
    error EscrowNotFunded(uint256 taskId);
    error RefundFailed(uint256 taskId, address recipient, uint256 amount);
    error PayoutFailed(uint256 taskId, address recipient, uint256 amount);

    event TaskIntentFunded(uint256 indexed taskId, address indexed payer, uint256 amount);
    event CancelledTaskIntentRefunded(uint256 indexed taskId, address indexed payer, uint256 amount);
    event AcceptedTaskIntentPaid(
        uint256 indexed taskId, bytes32 indexed agentId, address indexed recipient, uint256 amount
    );

    AgentRegistry public immutable agentRegistry;
    TaskIntentMarket public immutable taskIntentMarket;
    TaskAcceptanceRegistry public immutable taskAcceptanceRegistry;

    mapping(uint256 taskId => EscrowRecord record) private escrowRecords;

    constructor(address agentRegistry_, address taskIntentMarket_, address taskAcceptanceRegistry_) {
        if (agentRegistry_.code.length == 0) {
            revert InvalidAgentRegistry();
        }

        if (taskIntentMarket_.code.length == 0) {
            revert InvalidTaskIntentMarket();
        }

        if (taskAcceptanceRegistry_.code.length == 0) {
            revert InvalidTaskAcceptanceRegistry();
        }

        agentRegistry = AgentRegistry(agentRegistry_);
        taskIntentMarket = TaskIntentMarket(taskIntentMarket_);
        taskAcceptanceRegistry = TaskAcceptanceRegistry(taskAcceptanceRegistry_);
    }

    function fundTaskIntent(uint256 taskId) external payable {
        if (msg.value == 0) {
            revert InvalidFundingAmount();
        }

        TaskIntentMarket.TaskIntent memory intent = taskIntentMarket.getTaskIntent(taskId);

        if (intent.status != TaskIntentMarket.TaskStatus.Open) {
            revert TaskNotOpen(taskId);
        }

        if (msg.sender != intent.requester) {
            revert NotTaskRequester(taskId, msg.sender);
        }

        EscrowRecord storage record = escrowRecords[taskId];

        if (record.status != EscrowStatus.None) {
            revert EscrowAlreadyFunded(taskId);
        }

        escrowRecords[taskId] = EscrowRecord({payer: msg.sender, amount: msg.value, status: EscrowStatus.Funded});

        emit TaskIntentFunded(taskId, msg.sender, msg.value);
    }

    function refundCancelledTaskIntent(uint256 taskId) external {
        EscrowRecord storage record = escrowRecords[taskId];

        if (record.status != EscrowStatus.Funded) {
            revert EscrowNotFunded(taskId);
        }

        TaskIntentMarket.TaskIntent memory intent = taskIntentMarket.getTaskIntent(taskId);

        if (intent.status != TaskIntentMarket.TaskStatus.Cancelled) {
            revert TaskNotCancelled(taskId);
        }

        if (msg.sender != record.payer) {
            revert NotEscrowPayer(taskId, msg.sender);
        }

        uint256 amount = record.amount;
        record.status = EscrowStatus.Refunded;

        (bool refunded,) = msg.sender.call{value: amount}("");

        if (!refunded) {
            revert RefundFailed(taskId, msg.sender, amount);
        }

        emit CancelledTaskIntentRefunded(taskId, msg.sender, amount);
    }

    function releaseAcceptedTaskIntent(uint256 taskId) external {
        EscrowRecord storage record = escrowRecords[taskId];

        if (record.status != EscrowStatus.Funded) {
            revert EscrowNotFunded(taskId);
        }

        TaskIntentMarket.TaskIntent memory intent = taskIntentMarket.getTaskIntent(taskId);

        if (intent.status != TaskIntentMarket.TaskStatus.Assigned) {
            revert TaskNotAssigned(taskId);
        }

        TaskAcceptanceRegistry.AcceptanceRecord memory acceptance = taskAcceptanceRegistry.getAcceptanceRecord(taskId);

        if (acceptance.resultHash == bytes32(0)) {
            revert TaskResultNotAccepted(taskId);
        }

        address recipient = agentRegistry.ownerOf(intent.assignedAgentId);
        uint256 amount = record.amount;
        record.status = EscrowStatus.Released;

        (bool paid,) = recipient.call{value: amount}("");

        if (!paid) {
            revert PayoutFailed(taskId, recipient, amount);
        }

        emit AcceptedTaskIntentPaid(taskId, intent.assignedAgentId, recipient, amount);
    }

    function getEscrowRecord(uint256 taskId) external view returns (EscrowRecord memory) {
        return escrowRecords[taskId];
    }
}
