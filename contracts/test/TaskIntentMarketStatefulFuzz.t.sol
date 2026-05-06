// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {PolicyRootChain} from "../src/PolicyRootChain.sol";
import {TaskIntentMarket} from "../src/TaskIntentMarket.sol";

contract MockTaskAuthorizationGate {
    mapping(bytes32 agentId => bool authorized) public authorizedAgent;

    function setAuthorizedAgent(bytes32 agentId, bool authorized) external {
        authorizedAgent[agentId] = authorized;
    }

    function isTaskAuthorized(bytes32 agentId, bytes calldata, bytes32) external view returns (bool) {
        return authorizedAgent[agentId];
    }
}

contract TaskIntentMarketHandler is Test {
    uint256 internal constant MAX_TRACKED_TASKS = 32;

    struct ExpectedTaskIntent {
        address requester;
        bytes32 actionHash;
        bytes32 taskDataHash;
        bytes32 assignedAgentId;
        uint64 createdAt;
        uint64 assignedAt;
        TaskIntentMarket.TaskStatus status;
    }

    AgentRegistry public immutable registry;
    MockTaskAuthorizationGate public immutable gate;
    TaskIntentMarket public immutable market;

    bytes32[3] public agentIds;
    address[3] public agentOwners;

    uint256 public openedCount;

    mapping(uint256 taskId => ExpectedTaskIntent intent) internal expectedIntents;

    constructor(AgentRegistry registry_, MockTaskAuthorizationGate gate_, TaskIntentMarket market_) {
        registry = registry_;
        gate = gate_;
        market = market_;

        agentIds[0] = keccak256("emtun.intent.agent.alpha");
        agentIds[1] = keccak256("emtun.intent.agent.beta");
        agentIds[2] = keccak256("emtun.intent.agent.gamma");

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

    function expectedIntent(uint256 taskId) external view returns (ExpectedTaskIntent memory) {
        return expectedIntents[taskId];
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

    function _agentId(uint8 seed) internal view returns (bytes32) {
        return agentIds[uint256(seed) % agentIds.length];
    }

    function _agentOwner(uint8 seed) internal view returns (address) {
        return agentOwners[uint256(seed) % agentOwners.length];
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

contract TaskIntentMarketStatefulFuzzTest is Test {
    AgentRegistry internal registry;
    MockTaskAuthorizationGate internal gate;
    PolicyRootChain internal rootChain;
    TaskIntentMarket internal market;
    TaskIntentMarketHandler internal handler;

    function setUp() public {
        rootChain = new PolicyRootChain();
        registry = new AgentRegistry(address(rootChain));
        gate = new MockTaskAuthorizationGate();
        market = new TaskIntentMarket(address(registry), address(gate));
        handler = new TaskIntentMarketHandler(registry, gate, market);

        uint256 count = handler.agentCount();

        for (uint256 i = 0; i < count; i++) {
            bytes32 agentId = handler.agentIds(i);
            address owner = handler.agentOwners(i);
            bytes32 root = keccak256(abi.encode("task.intent.invariant.root", agentId));

            vm.prank(owner);
            registry.registerAgent(agentId, root);
            gate.setAuthorizedAgent(agentId, true);
        }
    }

    function testFuzz_TaskIntentStateMatchesModelAcrossOperationSequence(uint256 seed) public {
        for (uint256 i = 0; i < 64; i++) {
            uint256 step = uint256(keccak256(abi.encode(seed, i)));
            uint8 operation = uint8(step);

            if (operation % 3 == 0) {
                handler.openTaskIntent(uint8(step >> 8), uint128(step >> 16), uint128(step >> 144));
            } else if (operation % 3 == 1) {
                handler.claimTaskIntent(uint8(step >> 8), uint8(step >> 16), uint8(step >> 24));
            } else {
                handler.cancelTaskIntent(uint8(step >> 8), uint8(step >> 16));
            }
        }

        _assertNextTaskIdTracksOpenedTaskCount();
        _assertTaskStateMatchesModel();
        _assertAssignedAndCancelledTasksAreTerminal();
    }

    function _assertNextTaskIdTracksOpenedTaskCount() internal view {
        assertEq(market.nextTaskId(), handler.openedCount() + 1);
    }

    function _assertTaskStateMatchesModel() internal view {
        uint256 openedCount = handler.openedCount();

        for (uint256 taskId = 1; taskId <= openedCount; taskId++) {
            TaskIntentMarket.TaskIntent memory actual = market.getTaskIntent(taskId);
            TaskIntentMarketHandler.ExpectedTaskIntent memory expected = handler.expectedIntent(taskId);

            assertEq(actual.requester, expected.requester);
            assertEq(actual.actionHash, expected.actionHash);
            assertEq(actual.taskDataHash, expected.taskDataHash);
            assertEq(actual.assignedAgentId, expected.assignedAgentId);
            assertEq(actual.createdAt, expected.createdAt);
            assertEq(actual.assignedAt, expected.assignedAt);
            assertEq(uint8(actual.status), uint8(expected.status));
        }
    }

    function _assertAssignedAndCancelledTasksAreTerminal() internal view {
        uint256 openedCount = handler.openedCount();

        for (uint256 taskId = 1; taskId <= openedCount; taskId++) {
            TaskIntentMarket.TaskIntent memory intent = market.getTaskIntent(taskId);

            if (intent.status == TaskIntentMarket.TaskStatus.Open) {
                assertEq(intent.assignedAgentId, bytes32(0));
                assertEq(intent.assignedAt, 0);
                continue;
            }

            if (intent.status == TaskIntentMarket.TaskStatus.Assigned) {
                assertTrue(intent.assignedAgentId != bytes32(0));
                assertGe(intent.assignedAt, intent.createdAt);
                continue;
            }

            if (intent.status == TaskIntentMarket.TaskStatus.Cancelled) {
                assertEq(intent.assignedAgentId, bytes32(0));
                assertEq(intent.assignedAt, 0);
                continue;
            }

            revert("unexpected task status");
        }
    }
}
