// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AgentRegistry} from "./AgentRegistry.sol";
import {TaskIntentMarket} from "./TaskIntentMarket.sol";

contract TaskResultRegistry {
    struct ResultRecord {
        bytes32 agentId;
        bytes32 resultHash;
        uint64 submittedAt;
    }

    error InvalidAgentRegistry();
    error InvalidTaskIntentMarket();
    error InvalidResultHash();
    error TaskNotAssigned(uint256 taskId);
    error NotAssignedAgentOwner(uint256 taskId, bytes32 agentId, address caller);
    error ResultAlreadySubmitted(uint256 taskId, bytes32 resultHash);

    event TaskResultCommitted(
        uint256 indexed taskId, bytes32 indexed agentId, bytes32 indexed resultHash, address submitter
    );

    AgentRegistry public immutable agentRegistry;
    TaskIntentMarket public immutable taskIntentMarket;

    mapping(uint256 taskId => ResultRecord record) private resultRecords;

    constructor(address agentRegistry_, address taskIntentMarket_) {
        if (agentRegistry_.code.length == 0) {
            revert InvalidAgentRegistry();
        }

        if (taskIntentMarket_.code.length == 0) {
            revert InvalidTaskIntentMarket();
        }

        agentRegistry = AgentRegistry(agentRegistry_);
        taskIntentMarket = TaskIntentMarket(taskIntentMarket_);
    }

    function commitTaskResult(uint256 taskId, bytes32 resultHash) external {
        if (resultHash == bytes32(0)) {
            revert InvalidResultHash();
        }

        ResultRecord storage record = resultRecords[taskId];

        if (record.resultHash != bytes32(0)) {
            revert ResultAlreadySubmitted(taskId, record.resultHash);
        }

        TaskIntentMarket.TaskIntent memory intent = taskIntentMarket.getTaskIntent(taskId);

        if (intent.status != TaskIntentMarket.TaskStatus.Assigned) {
            revert TaskNotAssigned(taskId);
        }

        bytes32 agentId = intent.assignedAgentId;

        if (msg.sender != agentRegistry.ownerOf(agentId)) {
            revert NotAssignedAgentOwner(taskId, agentId, msg.sender);
        }

        resultRecords[taskId] =
            ResultRecord({agentId: agentId, resultHash: resultHash, submittedAt: uint64(block.timestamp)});

        emit TaskResultCommitted(taskId, agentId, resultHash, msg.sender);
    }

    function getResultRecord(uint256 taskId) external view returns (ResultRecord memory) {
        return resultRecords[taskId];
    }
}
