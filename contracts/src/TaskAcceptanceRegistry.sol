// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {TaskIntentMarket} from "./TaskIntentMarket.sol";
import {TaskResultRegistry} from "./TaskResultRegistry.sol";

contract TaskAcceptanceRegistry {
    struct AcceptanceRecord {
        address acceptedBy;
        bytes32 resultHash;
        uint64 acceptedAt;
    }

    error InvalidTaskIntentMarket();
    error InvalidTaskResultRegistry();
    error InvalidResultHash();
    error TaskNotAssigned(uint256 taskId);
    error ResultNotSubmitted(uint256 taskId);
    error ResultHashMismatch(uint256 taskId, bytes32 expectedResultHash, bytes32 submittedResultHash);
    error NotTaskRequester(uint256 taskId, address caller);
    error ResultAlreadyAccepted(uint256 taskId, bytes32 resultHash);

    event TaskResultAccepted(uint256 indexed taskId, address indexed requester, bytes32 indexed resultHash);

    TaskIntentMarket public immutable taskIntentMarket;
    TaskResultRegistry public immutable taskResultRegistry;

    mapping(uint256 taskId => AcceptanceRecord record) private acceptanceRecords;

    constructor(address taskIntentMarket_, address taskResultRegistry_) {
        if (taskIntentMarket_.code.length == 0) {
            revert InvalidTaskIntentMarket();
        }

        if (taskResultRegistry_.code.length == 0) {
            revert InvalidTaskResultRegistry();
        }

        taskIntentMarket = TaskIntentMarket(taskIntentMarket_);
        taskResultRegistry = TaskResultRegistry(taskResultRegistry_);
    }

    function acceptTaskResult(uint256 taskId, bytes32 resultHash) external {
        if (resultHash == bytes32(0)) {
            revert InvalidResultHash();
        }

        AcceptanceRecord storage acceptance = acceptanceRecords[taskId];

        if (acceptance.resultHash != bytes32(0)) {
            revert ResultAlreadyAccepted(taskId, acceptance.resultHash);
        }

        TaskIntentMarket.TaskIntent memory intent = taskIntentMarket.getTaskIntent(taskId);

        if (intent.status != TaskIntentMarket.TaskStatus.Assigned) {
            revert TaskNotAssigned(taskId);
        }

        if (msg.sender != intent.requester) {
            revert NotTaskRequester(taskId, msg.sender);
        }

        TaskResultRegistry.ResultRecord memory result = taskResultRegistry.getResultRecord(taskId);

        if (result.resultHash == bytes32(0)) {
            revert ResultNotSubmitted(taskId);
        }

        if (resultHash != result.resultHash) {
            revert ResultHashMismatch(taskId, result.resultHash, resultHash);
        }

        acceptanceRecords[taskId] =
            AcceptanceRecord({acceptedBy: msg.sender, resultHash: resultHash, acceptedAt: uint64(block.timestamp)});

        emit TaskResultAccepted(taskId, msg.sender, resultHash);
    }

    function getAcceptanceRecord(uint256 taskId) external view returns (AcceptanceRecord memory) {
        return acceptanceRecords[taskId];
    }
}
