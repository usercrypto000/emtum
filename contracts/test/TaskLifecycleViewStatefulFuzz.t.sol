// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {PolicyRootChain} from "../src/PolicyRootChain.sol";
import {TaskAcceptanceRegistry} from "../src/TaskAcceptanceRegistry.sol";
import {TaskFundingEscrow} from "../src/TaskFundingEscrow.sol";
import {TaskIntentMarket} from "../src/TaskIntentMarket.sol";
import {TaskLifecycleView} from "../src/TaskLifecycleView.sol";
import {TaskResultRegistry} from "../src/TaskResultRegistry.sol";
import {MockSettlementAuthorizationGate, TaskSettlementHandler} from "./TaskSettlementStatefulFuzz.t.sol";

contract TaskLifecycleViewStatefulFuzzTest is Test {
    AgentRegistry internal registry;
    MockSettlementAuthorizationGate internal gate;
    PolicyRootChain internal rootChain;
    TaskIntentMarket internal market;
    TaskResultRegistry internal resultRegistry;
    TaskAcceptanceRegistry internal acceptanceRegistry;
    TaskFundingEscrow internal escrow;
    TaskLifecycleView internal lifecycleView;
    TaskSettlementHandler internal handler;

    function setUp() public {
        rootChain = new PolicyRootChain();
        registry = new AgentRegistry(address(rootChain));
        gate = new MockSettlementAuthorizationGate();
        market = new TaskIntentMarket(address(registry), address(gate));
        resultRegistry = new TaskResultRegistry(address(registry), address(market));
        acceptanceRegistry = new TaskAcceptanceRegistry(address(market), address(resultRegistry));
        escrow = new TaskFundingEscrow(address(registry), address(market), address(acceptanceRegistry));
        lifecycleView = new TaskLifecycleView(
            address(market), address(escrow), address(resultRegistry), address(acceptanceRegistry)
        );
        handler = new TaskSettlementHandler(registry, market, resultRegistry, acceptanceRegistry, escrow);

        uint256 actorCount = handler.actorCount();

        for (uint256 i = 0; i < actorCount; i++) {
            vm.deal(handler.actors(i), handler.initialBalance());
        }

        uint256 agentCount = handler.agentCount();

        for (uint256 i = 0; i < agentCount; i++) {
            bytes32 agentId = handler.agentIds(i);
            address owner = handler.agentOwners(i);
            bytes32 root = keccak256(abi.encode("task.lifecycle.view.invariant.root", agentId));

            vm.prank(owner);
            registry.registerAgent(agentId, root);
        }
    }

    function testFuzz_TaskLifecycleViewMirrorsUnderlyingState(uint256 seed) public {
        for (uint256 i = 0; i < 72; i++) {
            uint256 step = uint256(keccak256(abi.encode(seed, i)));
            uint8 operation = uint8(step);

            if (operation % 8 == 0) {
                handler.openTaskIntent(uint8(step >> 8), uint128(step >> 16), uint128(step >> 144));
            } else if (operation % 8 == 1) {
                handler.fundTaskIntent(uint8(step >> 8), uint8(step >> 16), uint128(step >> 24));
            } else if (operation % 8 == 2) {
                handler.claimTaskIntent(uint8(step >> 8), uint8(step >> 16), uint8(step >> 24));
            } else if (operation % 8 == 3) {
                handler.commitTaskResult(uint8(step >> 8), uint8(step >> 16), uint128(step >> 24));
            } else if (operation % 8 == 4) {
                handler.acceptTaskResult(uint8(step >> 8), uint8(step >> 16), uint8(step >> 24), uint128(step >> 32));
            } else if (operation % 8 == 5) {
                handler.releaseAcceptedTaskIntent(uint8(step >> 8));
            } else if (operation % 8 == 6) {
                handler.cancelTaskIntent(uint8(step >> 8), uint8(step >> 16));
            } else {
                handler.refundCancelledTaskIntent(uint8(step >> 8), uint8(step >> 16));
            }
        }

        uint256 openedCount = handler.openedCount();

        for (uint256 taskId = 1; taskId <= openedCount; taskId++) {
            _assertLifecycleMirrorsSources(taskId);
        }
    }

    function _assertLifecycleMirrorsSources(uint256 taskId) private view {
        TaskLifecycleView.TaskLifecycle memory lifecycle = lifecycleView.getTaskLifecycle(taskId);
        TaskIntentMarket.TaskIntent memory intent = market.getTaskIntent(taskId);
        TaskFundingEscrow.EscrowRecord memory escrowRecord = escrow.getEscrowRecord(taskId);
        TaskResultRegistry.ResultRecord memory result = resultRegistry.getResultRecord(taskId);
        TaskAcceptanceRegistry.AcceptanceRecord memory acceptance = acceptanceRegistry.getAcceptanceRecord(taskId);

        assertEq(uint8(lifecycle.taskStatus), uint8(intent.status));
        assertEq(uint8(lifecycle.escrowStatus), uint8(escrowRecord.status));
        assertEq(lifecycle.resultHash, result.resultHash);
        assertEq(lifecycle.acceptanceHash, acceptance.resultHash);
        assertEq(lifecycle.requester, intent.requester);
        assertEq(lifecycle.escrowPayer, escrowRecord.payer);
        assertEq(lifecycle.assignedAgentId, intent.assignedAgentId);
        assertEq(lifecycle.resultAgentId, result.agentId);
        assertEq(lifecycle.escrowAmount, escrowRecord.amount);
        assertEq(lifecycle.createdAt, intent.createdAt);
        assertEq(lifecycle.assignedAt, intent.assignedAt);
        assertEq(lifecycle.resultSubmittedAt, result.submittedAt);
        assertEq(lifecycle.acceptedAt, acceptance.acceptedAt);
        assertEq(lifecycle.isOpen, intent.status == TaskIntentMarket.TaskStatus.Open);
        assertEq(lifecycle.isAssigned, intent.status == TaskIntentMarket.TaskStatus.Assigned);
        assertEq(lifecycle.isCancelled, intent.status == TaskIntentMarket.TaskStatus.Cancelled);
        assertEq(lifecycle.isFunded, escrowRecord.status == TaskFundingEscrow.EscrowStatus.Funded);
        assertEq(lifecycle.isRefunded, escrowRecord.status == TaskFundingEscrow.EscrowStatus.Refunded);
        assertEq(lifecycle.isReleased, escrowRecord.status == TaskFundingEscrow.EscrowStatus.Released);
        assertEq(lifecycle.isResultCommitted, result.resultHash != bytes32(0));
        assertEq(lifecycle.isAccepted, acceptance.resultHash != bytes32(0));
    }
}
