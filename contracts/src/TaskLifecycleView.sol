// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {TaskAcceptanceRegistry} from "./TaskAcceptanceRegistry.sol";
import {TaskFundingEscrow} from "./TaskFundingEscrow.sol";
import {TaskIntentMarket} from "./TaskIntentMarket.sol";
import {TaskResultRegistry} from "./TaskResultRegistry.sol";

contract TaskLifecycleView {
    struct TaskLifecycle {
        TaskIntentMarket.TaskStatus taskStatus;
        TaskFundingEscrow.EscrowStatus escrowStatus;
        bytes32 resultHash;
        bytes32 acceptanceHash;
        address requester;
        bytes32 assignedAgentId;
        uint256 escrowAmount;
    }

    error InvalidTaskIntentMarket();
    error InvalidTaskFundingEscrow();
    error InvalidTaskResultRegistry();
    error InvalidTaskAcceptanceRegistry();

    TaskIntentMarket public immutable taskIntentMarket;
    TaskFundingEscrow public immutable taskFundingEscrow;
    TaskResultRegistry public immutable taskResultRegistry;
    TaskAcceptanceRegistry public immutable taskAcceptanceRegistry;

    constructor(
        address taskIntentMarket_,
        address taskFundingEscrow_,
        address taskResultRegistry_,
        address taskAcceptanceRegistry_
    ) {
        if (taskIntentMarket_.code.length == 0) {
            revert InvalidTaskIntentMarket();
        }

        if (taskFundingEscrow_.code.length == 0) {
            revert InvalidTaskFundingEscrow();
        }

        if (taskResultRegistry_.code.length == 0) {
            revert InvalidTaskResultRegistry();
        }

        if (taskAcceptanceRegistry_.code.length == 0) {
            revert InvalidTaskAcceptanceRegistry();
        }

        taskIntentMarket = TaskIntentMarket(taskIntentMarket_);
        taskFundingEscrow = TaskFundingEscrow(taskFundingEscrow_);
        taskResultRegistry = TaskResultRegistry(taskResultRegistry_);
        taskAcceptanceRegistry = TaskAcceptanceRegistry(taskAcceptanceRegistry_);
    }

    function getTaskLifecycle(uint256 taskId) external view returns (TaskLifecycle memory lifecycle) {
        TaskIntentMarket.TaskIntent memory intent = taskIntentMarket.getTaskIntent(taskId);
        TaskFundingEscrow.EscrowRecord memory escrow = taskFundingEscrow.getEscrowRecord(taskId);
        TaskResultRegistry.ResultRecord memory result = taskResultRegistry.getResultRecord(taskId);
        TaskAcceptanceRegistry.AcceptanceRecord memory acceptance = taskAcceptanceRegistry.getAcceptanceRecord(taskId);

        lifecycle = TaskLifecycle({
            taskStatus: intent.status,
            escrowStatus: escrow.status,
            resultHash: result.resultHash,
            acceptanceHash: acceptance.resultHash,
            requester: intent.requester,
            assignedAgentId: intent.assignedAgentId,
            escrowAmount: escrow.amount
        });
    }
}
