// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AgentRegistry} from "./AgentRegistry.sol";
import {TaskAuthorizationGate} from "./TaskAuthorizationGate.sol";

contract TaskIntentMarket {
    enum TaskStatus {
        None,
        Open,
        Assigned,
        Cancelled
    }

    struct TaskIntent {
        address requester;
        bytes32 actionHash;
        bytes32 taskDataHash;
        bytes32 assignedAgentId;
        uint64 createdAt;
        uint64 assignedAt;
        TaskStatus status;
    }

    error InvalidAuthorizationGate();
    error InvalidAgentRegistry();
    error InvalidActionHash();
    error InvalidTaskDataHash();
    error NotAgentOwner(bytes32 agentId, address caller);
    error TaskNotOpen(uint256 taskId);
    error NotTaskRequester(uint256 taskId, address caller);
    error UnauthorizedTaskClaim(uint256 taskId, bytes32 agentId, bytes32 actionHash);

    event TaskIntentOpened(
        uint256 indexed taskId, address indexed requester, bytes32 indexed actionHash, bytes32 taskDataHash
    );
    event TaskIntentClaimed(uint256 indexed taskId, bytes32 indexed agentId, bytes32 indexed actionHash);
    event TaskIntentCancelled(uint256 indexed taskId, address indexed requester);

    AgentRegistry public immutable agentRegistry;
    TaskAuthorizationGate public immutable authorizationGate;

    uint256 public nextTaskId = 1;

    mapping(uint256 taskId => TaskIntent intent) private taskIntents;

    constructor(address agentRegistry_, address authorizationGate_) {
        if (agentRegistry_.code.length == 0) {
            revert InvalidAgentRegistry();
        }

        if (authorizationGate_.code.length == 0) {
            revert InvalidAuthorizationGate();
        }

        agentRegistry = AgentRegistry(agentRegistry_);
        authorizationGate = TaskAuthorizationGate(authorizationGate_);
    }

    function openTaskIntent(bytes32 actionHash, bytes32 taskDataHash) external returns (uint256 taskId) {
        if (actionHash == bytes32(0)) {
            revert InvalidActionHash();
        }

        if (taskDataHash == bytes32(0)) {
            revert InvalidTaskDataHash();
        }

        taskId = nextTaskId;
        nextTaskId += 1;

        taskIntents[taskId] = TaskIntent({
            requester: msg.sender,
            actionHash: actionHash,
            taskDataHash: taskDataHash,
            assignedAgentId: bytes32(0),
            createdAt: uint64(block.timestamp),
            assignedAt: 0,
            status: TaskStatus.Open
        });

        emit TaskIntentOpened(taskId, msg.sender, actionHash, taskDataHash);
    }

    function claimTaskIntent(uint256 taskId, bytes32 agentId, bytes calldata proof) external {
        TaskIntent storage intent = taskIntents[taskId];

        if (intent.status != TaskStatus.Open) {
            revert TaskNotOpen(taskId);
        }

        if (msg.sender != agentRegistry.ownerOf(agentId)) {
            revert NotAgentOwner(agentId, msg.sender);
        }

        if (!authorizationGate.isTaskAuthorized(agentId, proof, intent.actionHash)) {
            revert UnauthorizedTaskClaim(taskId, agentId, intent.actionHash);
        }

        intent.assignedAgentId = agentId;
        intent.assignedAt = uint64(block.timestamp);
        intent.status = TaskStatus.Assigned;

        emit TaskIntentClaimed(taskId, agentId, intent.actionHash);
    }

    function cancelTaskIntent(uint256 taskId) external {
        TaskIntent storage intent = taskIntents[taskId];

        if (intent.status != TaskStatus.Open) {
            revert TaskNotOpen(taskId);
        }

        if (msg.sender != intent.requester) {
            revert NotTaskRequester(taskId, msg.sender);
        }

        intent.status = TaskStatus.Cancelled;

        emit TaskIntentCancelled(taskId, msg.sender);
    }

    function getTaskIntent(uint256 taskId) external view returns (TaskIntent memory) {
        return taskIntents[taskId];
    }
}
