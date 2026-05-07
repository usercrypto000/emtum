// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {PolicyRootChain} from "../src/PolicyRootChain.sol";
import {TaskIntentMarket} from "../src/TaskIntentMarket.sol";
import {TaskResultRegistry} from "../src/TaskResultRegistry.sol";

contract MockTaskResultAuthorizationGate {
    mapping(bytes32 agentId => bool authorized) public authorizedAgent;

    function setAuthorizedAgent(bytes32 agentId, bool authorized) external {
        authorizedAgent[agentId] = authorized;
    }

    function isTaskAuthorized(bytes32 agentId, bytes calldata, bytes32) external view returns (bool) {
        return authorizedAgent[agentId];
    }
}

contract TaskResultRegistryHandler is Test {
    uint256 internal constant MAX_TRACKED_TASKS = 24;

    struct ExpectedTaskIntent {
        address requester;
        bytes32 actionHash;
        bytes32 taskDataHash;
        bytes32 assignedAgentId;
        uint64 createdAt;
        uint64 assignedAt;
        TaskIntentMarket.TaskStatus status;
    }

    struct ExpectedResultRecord {
        bytes32 agentId;
        bytes32 resultHash;
        uint64 submittedAt;
        bool submitted;
    }

    AgentRegistry public immutable registry;
    MockTaskResultAuthorizationGate public immutable gate;
    TaskIntentMarket public immutable market;
    TaskResultRegistry public immutable resultRegistry;

    bytes32[3] public agentIds;
    address[3] public agentOwners;

    uint256 public openedCount;

    mapping(uint256 taskId => ExpectedTaskIntent intent) internal expectedIntents;
    mapping(uint256 taskId => ExpectedResultRecord record) internal expectedResults;

    constructor(
        AgentRegistry registry_,
        MockTaskResultAuthorizationGate gate_,
        TaskIntentMarket market_,
        TaskResultRegistry resultRegistry_
    ) {
        registry = registry_;
        gate = gate_;
        market = market_;
        resultRegistry = resultRegistry_;

        agentIds[0] = keccak256("emtun.result.agent.alpha");
        agentIds[1] = keccak256("emtun.result.agent.beta");
        agentIds[2] = keccak256("emtun.result.agent.gamma");

        agentOwners[0] = address(0xA11CE);
        agentOwners[1] = address(0xB0B);
        agentOwners[2] = address(0xCA11);
    }

    function openTaskIntent(uint8 requesterSeed, uint128 actionSeed, uint128 dataSeed) external {
        if (openedCount >= MAX_TRACKED_TASKS) {
            return;
        }

        address requester = _actor(requesterSeed);
        bytes32 actionHash = _nonZeroHash("action", actionSeed);
        bytes32 taskDataHash = _nonZeroHash("task.data", dataSeed);

        vm.prank(requester);
        uint256 taskId = market.openTaskIntent(actionHash, taskDataHash);

        openedCount += 1;

        assertEq(taskId, openedCount);

        expectedIntents[taskId] = ExpectedTaskIntent({
            requester: requester,
            actionHash: actionHash,
            taskDataHash: taskDataHash,
            assignedAgentId: bytes32(0),
            createdAt: uint64(block.timestamp),
            assignedAt: 0,
            status: TaskIntentMarket.TaskStatus.Open
        });
    }

    function claimTaskIntent(uint8 taskSeed, uint8 agentSeed, uint8 actorSeed) external {
        uint256 taskId = _taskId(taskSeed);
        ExpectedTaskIntent storage expected = expectedIntents[taskId];
        bytes32 agentId = _agentId(agentSeed);
        address owner = _agentOwner(agentSeed);
        address actor = _actor(actorSeed);

        if (expected.status != TaskIntentMarket.TaskStatus.Open) {
            vm.expectRevert(abi.encodeWithSelector(TaskIntentMarket.TaskNotOpen.selector, taskId));
            vm.prank(actor);
            market.claimTaskIntent(taskId, agentId, "");
            return;
        }

        if (actor != owner) {
            vm.expectRevert(abi.encodeWithSelector(TaskIntentMarket.NotAgentOwner.selector, agentId, actor));
            vm.prank(actor);
            market.claimTaskIntent(taskId, agentId, "");
            return;
        }

        vm.prank(actor);
        market.claimTaskIntent(taskId, agentId, "");

        expected.assignedAgentId = agentId;
        expected.assignedAt = uint64(block.timestamp);
        expected.status = TaskIntentMarket.TaskStatus.Assigned;
    }

    function cancelTaskIntent(uint8 taskSeed, uint8 actorSeed) external {
        uint256 taskId = _taskId(taskSeed);
        ExpectedTaskIntent storage expected = expectedIntents[taskId];
        address actor = _actor(actorSeed);

        if (expected.status != TaskIntentMarket.TaskStatus.Open) {
            vm.expectRevert(abi.encodeWithSelector(TaskIntentMarket.TaskNotOpen.selector, taskId));
            vm.prank(actor);
            market.cancelTaskIntent(taskId);
            return;
        }

        if (actor != expected.requester) {
            vm.expectRevert(abi.encodeWithSelector(TaskIntentMarket.NotTaskRequester.selector, taskId, actor));
            vm.prank(actor);
            market.cancelTaskIntent(taskId);
            return;
        }

        vm.prank(actor);
        market.cancelTaskIntent(taskId);

        expected.status = TaskIntentMarket.TaskStatus.Cancelled;
    }

    function transferAgentOwner(uint8 agentSeed, uint8 actorSeed, uint8 newOwnerSeed) external {
        uint256 agentIndex = uint256(agentSeed) % agentIds.length;
        bytes32 agentId = agentIds[agentIndex];
        address currentOwner = agentOwners[agentIndex];
        address actor = _actor(actorSeed);
        address newOwner = _actor(newOwnerSeed);

        if (actor != currentOwner) {
            vm.expectRevert(abi.encodeWithSelector(AgentRegistry.NotAgentOwner.selector, agentId, actor));
            vm.prank(actor);
            registry.transferAgentOwner(agentId, newOwner);
            return;
        }

        vm.prank(actor);
        registry.transferAgentOwner(agentId, newOwner);

        agentOwners[agentIndex] = newOwner;
    }

    function commitTaskResult(uint8 taskSeed, uint8 actorSeed, uint128 resultSeed) external {
        uint256 taskId = _taskId(taskSeed);
        ExpectedTaskIntent storage intentModel = expectedIntents[taskId];
        ExpectedResultRecord storage resultModel = expectedResults[taskId];
        address actor = _actor(actorSeed);
        bytes32 resultHash = _nonZeroHash("task.result", resultSeed);

        if (resultModel.submitted) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    TaskResultRegistry.ResultAlreadySubmitted.selector, taskId, resultModel.resultHash
                )
            );
            vm.prank(actor);
            resultRegistry.commitTaskResult(taskId, resultHash);
            return;
        }

        if (intentModel.status != TaskIntentMarket.TaskStatus.Assigned) {
            vm.expectRevert(abi.encodeWithSelector(TaskResultRegistry.TaskNotAssigned.selector, taskId));
            vm.prank(actor);
            resultRegistry.commitTaskResult(taskId, resultHash);
            return;
        }

        bytes32 agentId = intentModel.assignedAgentId;

        if (actor != _agentOwnerById(agentId)) {
            vm.expectRevert(
                abi.encodeWithSelector(TaskResultRegistry.NotAssignedAgentOwner.selector, taskId, agentId, actor)
            );
            vm.prank(actor);
            resultRegistry.commitTaskResult(taskId, resultHash);
            return;
        }

        vm.prank(actor);
        resultRegistry.commitTaskResult(taskId, resultHash);

        resultModel.agentId = agentId;
        resultModel.resultHash = resultHash;
        resultModel.submittedAt = uint64(block.timestamp);
        resultModel.submitted = true;
    }

    function invalidActorCommitAttempt(uint8 taskSeed, uint8 actorSeed, uint128 resultSeed) external {
        uint256 taskId = _assignedTaskWithoutResult(taskSeed);

        if (taskId == 0) {
            return;
        }

        ExpectedTaskIntent storage expected = expectedIntents[taskId];
        bytes32 agentId = expected.assignedAgentId;
        address actor = _nonOwnerActor(agentId, actorSeed);
        bytes32 resultHash = _nonZeroHash("invalid.actor.result", resultSeed);

        vm.expectRevert(
            abi.encodeWithSelector(TaskResultRegistry.NotAssignedAgentOwner.selector, taskId, agentId, actor)
        );
        vm.prank(actor);
        resultRegistry.commitTaskResult(taskId, resultHash);
    }

    function invalidZeroResultAttempt(uint8 taskSeed, uint8 actorSeed) external {
        uint256 taskId = _taskId(taskSeed);
        address actor = _actor(actorSeed);

        vm.expectRevert(TaskResultRegistry.InvalidResultHash.selector);
        vm.prank(actor);
        resultRegistry.commitTaskResult(taskId, bytes32(0));
    }

    function expectedIntent(uint256 taskId) external view returns (ExpectedTaskIntent memory) {
        return expectedIntents[taskId];
    }

    function expectedResult(uint256 taskId) external view returns (ExpectedResultRecord memory) {
        return expectedResults[taskId];
    }

    function agentCount() external pure returns (uint256) {
        return 3;
    }

    function _taskId(uint8 seed) internal view returns (uint256) {
        uint256 count = openedCount;

        if (count == 0) {
            return 1;
        }

        return (uint256(seed) % count) + 1;
    }

    function _assignedTaskWithoutResult(uint8 seed) internal view returns (uint256) {
        uint256 count = openedCount;

        if (count == 0) {
            return 0;
        }

        uint256 offset = uint256(seed) % count;

        for (uint256 i = 0; i < count; i++) {
            uint256 taskId = ((offset + i) % count) + 1;

            if (
                expectedIntents[taskId].status == TaskIntentMarket.TaskStatus.Assigned
                    && !expectedResults[taskId].submitted
            ) {
                return taskId;
            }
        }

        return 0;
    }

    function _agentId(uint8 seed) internal view returns (bytes32) {
        return agentIds[uint256(seed) % agentIds.length];
    }

    function _agentOwner(uint8 seed) internal view returns (address) {
        return agentOwners[uint256(seed) % agentOwners.length];
    }

    function _agentOwnerById(bytes32 agentId) internal view returns (address) {
        for (uint256 i = 0; i < agentIds.length; i++) {
            if (agentIds[i] == agentId) {
                return agentOwners[i];
            }
        }

        revert("unknown agent");
    }

    function _nonOwnerActor(bytes32 agentId, uint8 seed) internal view returns (address) {
        address owner = _agentOwnerById(agentId);
        address actor = _actor(seed);

        if (actor != owner) {
            return actor;
        }

        return address(uint160(owner) + 1);
    }

    function _actor(uint8 seed) internal view returns (address) {
        uint256 index = uint256(seed) % 6;

        if (index < agentOwners.length) {
            return agentOwners[index];
        }

        return address(uint160(index + 1));
    }

    function _nonZeroHash(string memory domain, uint128 seed) internal pure returns (bytes32 hash) {
        hash = keccak256(abi.encode(domain, seed));

        if (hash == bytes32(0)) {
            return keccak256(abi.encode(domain, uint256(1)));
        }
    }
}

contract TaskResultRegistryStatefulFuzzTest is Test {
    AgentRegistry internal registry;
    MockTaskResultAuthorizationGate internal gate;
    PolicyRootChain internal rootChain;
    TaskIntentMarket internal market;
    TaskResultRegistry internal resultRegistry;
    TaskResultRegistryHandler internal handler;

    function setUp() public {
        rootChain = new PolicyRootChain();
        registry = new AgentRegistry(address(rootChain));
        gate = new MockTaskResultAuthorizationGate();
        market = new TaskIntentMarket(address(registry), address(gate));
        resultRegistry = new TaskResultRegistry(address(registry), address(market));
        handler = new TaskResultRegistryHandler(registry, gate, market, resultRegistry);

        uint256 count = handler.agentCount();

        for (uint256 i = 0; i < count; i++) {
            bytes32 agentId = handler.agentIds(i);
            address owner = handler.agentOwners(i);
            bytes32 root = keccak256(abi.encode("task.result.invariant.root", agentId));

            vm.prank(owner);
            registry.registerAgent(agentId, root);
            gate.setAuthorizedAgent(agentId, true);
        }
    }

    function testFuzz_TaskResultStateMatchesModelAcrossOperationSequence(uint256 seed) public {
        for (uint256 i = 0; i < 64; i++) {
            uint256 step = uint256(keccak256(abi.encode(seed, i)));
            uint8 operation = uint8(step);

            if (operation % 7 == 0) {
                handler.openTaskIntent(uint8(step >> 8), uint128(step >> 16), uint128(step >> 144));
            } else if (operation % 7 == 1) {
                handler.claimTaskIntent(uint8(step >> 8), uint8(step >> 16), uint8(step >> 24));
            } else if (operation % 7 == 2) {
                handler.cancelTaskIntent(uint8(step >> 8), uint8(step >> 16));
            } else if (operation % 7 == 3) {
                handler.transferAgentOwner(uint8(step >> 8), uint8(step >> 16), uint8(step >> 24));
            } else if (operation % 7 == 4) {
                handler.commitTaskResult(uint8(step >> 8), uint8(step >> 16), uint128(step >> 24));
            } else if (operation % 7 == 5) {
                handler.invalidActorCommitAttempt(uint8(step >> 8), uint8(step >> 16), uint128(step >> 24));
            } else {
                handler.invalidZeroResultAttempt(uint8(step >> 8), uint8(step >> 16));
            }
        }

        _assertNextTaskIdTracksOpenedTaskCount();
        _assertTaskStateMatchesModel();
        _assertResultRecordsMatchModel();
        _assertOnlyAssignedTasksHaveResultRecords();
    }

    function _assertNextTaskIdTracksOpenedTaskCount() internal view {
        assertEq(market.nextTaskId(), handler.openedCount() + 1);
    }

    function _assertTaskStateMatchesModel() internal view {
        uint256 openedCount = handler.openedCount();

        for (uint256 taskId = 1; taskId <= openedCount; taskId++) {
            TaskIntentMarket.TaskIntent memory actual = market.getTaskIntent(taskId);
            TaskResultRegistryHandler.ExpectedTaskIntent memory expected = handler.expectedIntent(taskId);

            assertEq(actual.requester, expected.requester);
            assertEq(actual.actionHash, expected.actionHash);
            assertEq(actual.taskDataHash, expected.taskDataHash);
            assertEq(actual.assignedAgentId, expected.assignedAgentId);
            assertEq(actual.createdAt, expected.createdAt);
            assertEq(actual.assignedAt, expected.assignedAt);
            assertEq(uint8(actual.status), uint8(expected.status));
        }
    }

    function _assertResultRecordsMatchModel() internal view {
        uint256 openedCount = handler.openedCount();

        for (uint256 taskId = 1; taskId <= openedCount; taskId++) {
            TaskResultRegistry.ResultRecord memory actual = resultRegistry.getResultRecord(taskId);
            TaskResultRegistryHandler.ExpectedResultRecord memory expected = handler.expectedResult(taskId);

            if (!expected.submitted) {
                assertEq(actual.agentId, bytes32(0));
                assertEq(actual.resultHash, bytes32(0));
                assertEq(actual.submittedAt, 0);
                continue;
            }

            assertEq(actual.agentId, expected.agentId);
            assertEq(actual.resultHash, expected.resultHash);
            assertEq(actual.submittedAt, expected.submittedAt);
            assertTrue(actual.resultHash != bytes32(0));
            assertGt(actual.submittedAt, 0);
        }
    }

    function _assertOnlyAssignedTasksHaveResultRecords() internal view {
        uint256 openedCount = handler.openedCount();

        for (uint256 taskId = 1; taskId <= openedCount; taskId++) {
            TaskIntentMarket.TaskIntent memory intent = market.getTaskIntent(taskId);
            TaskResultRegistry.ResultRecord memory record = resultRegistry.getResultRecord(taskId);

            if (
                intent.status == TaskIntentMarket.TaskStatus.Open
                    || intent.status == TaskIntentMarket.TaskStatus.Cancelled
            ) {
                assertEq(record.agentId, bytes32(0));
                assertEq(record.resultHash, bytes32(0));
                assertEq(record.submittedAt, 0);
                continue;
            }

            if (record.resultHash != bytes32(0)) {
                assertEq(uint8(intent.status), uint8(TaskIntentMarket.TaskStatus.Assigned));
                assertEq(record.agentId, intent.assignedAgentId);
            }
        }
    }
}
