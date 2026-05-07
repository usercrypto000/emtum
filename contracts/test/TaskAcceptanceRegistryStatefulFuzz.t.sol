// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {PolicyRootChain} from "../src/PolicyRootChain.sol";
import {TaskAcceptanceRegistry} from "../src/TaskAcceptanceRegistry.sol";
import {TaskIntentMarket} from "../src/TaskIntentMarket.sol";
import {TaskResultRegistry} from "../src/TaskResultRegistry.sol";

contract MockAcceptanceTaskAuthorizationGate {
    mapping(bytes32 agentId => bool authorized) public authorizedAgent;

    function setAuthorizedAgent(bytes32 agentId, bool authorized) external {
        authorizedAgent[agentId] = authorized;
    }

    function isTaskAuthorized(bytes32 agentId, bytes calldata, bytes32) external view returns (bool) {
        return authorizedAgent[agentId];
    }
}

contract TaskAcceptanceRegistryHandler is Test {
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

    struct ExpectedResultRecord {
        bytes32 agentId;
        bytes32 resultHash;
        uint64 submittedAt;
    }

    struct ExpectedAcceptanceRecord {
        address acceptedBy;
        bytes32 resultHash;
        uint64 acceptedAt;
    }

    AgentRegistry public immutable registry;
    MockAcceptanceTaskAuthorizationGate public immutable gate;
    TaskIntentMarket public immutable market;
    TaskResultRegistry public immutable resultRegistry;
    TaskAcceptanceRegistry public immutable acceptanceRegistry;

    bytes32[3] public agentIds;
    address[3] public agentOwners;

    uint256 public openedCount;

    mapping(uint256 taskId => ExpectedTaskIntent intent) internal expectedIntents;
    mapping(uint256 taskId => ExpectedResultRecord record) internal expectedResults;
    mapping(uint256 taskId => ExpectedAcceptanceRecord record) internal expectedAcceptances;

    constructor(
        AgentRegistry registry_,
        MockAcceptanceTaskAuthorizationGate gate_,
        TaskIntentMarket market_,
        TaskResultRegistry resultRegistry_,
        TaskAcceptanceRegistry acceptanceRegistry_
    ) {
        registry = registry_;
        gate = gate_;
        market = market_;
        resultRegistry = resultRegistry_;
        acceptanceRegistry = acceptanceRegistry_;

        agentIds[0] = keccak256("emtun.acceptance.agent.alpha");
        agentIds[1] = keccak256("emtun.acceptance.agent.beta");
        agentIds[2] = keccak256("emtun.acceptance.agent.gamma");

        agentOwners[0] = address(0xA11CE);
        agentOwners[1] = address(0xB0B);
        agentOwners[2] = address(0xCA11);
    }

    function seedAcceptedTaskWithRejectedAcceptanceAttempts(uint8 requesterSeed, uint8 agentSeed, uint128 resultSeed)
        external
    {
        if (openedCount >= MAX_TRACKED_TASKS) {
            return;
        }

        address requester = _actor(requesterSeed);
        bytes32 agentId = _agentId(agentSeed);
        address owner = _agentOwner(agentSeed);
        bytes32 actionHash = _nonZeroHash("seed.action", resultSeed);
        bytes32 taskDataHash = _nonZeroHash("seed.task.data", resultSeed);
        bytes32 resultHash = _nonZeroHash("seed.result", resultSeed);
        bytes32 wrongResultHash = _differentHash("seed.wrong.result", resultSeed, resultHash);

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

        vm.prank(owner);
        market.claimTaskIntent(taskId, agentId, "");

        expectedIntents[taskId].assignedAgentId = agentId;
        expectedIntents[taskId].assignedAt = uint64(block.timestamp);
        expectedIntents[taskId].status = TaskIntentMarket.TaskStatus.Assigned;

        _expectAcceptanceUnchanged(
            taskId,
            abi.encodeWithSelector(TaskAcceptanceRegistry.ResultNotSubmitted.selector, taskId),
            requester,
            resultHash
        );

        vm.prank(owner);
        resultRegistry.commitTaskResult(taskId, resultHash);

        expectedResults[taskId] =
            ExpectedResultRecord({agentId: agentId, resultHash: resultHash, submittedAt: uint64(block.timestamp)});

        _expectAcceptanceUnchanged(
            taskId,
            abi.encodeWithSelector(
                TaskAcceptanceRegistry.ResultHashMismatch.selector, taskId, resultHash, wrongResultHash
            ),
            requester,
            wrongResultHash
        );

        address nonRequester = _otherActor(requesterSeed);

        _expectAcceptanceUnchanged(
            taskId,
            abi.encodeWithSelector(TaskAcceptanceRegistry.NotTaskRequester.selector, taskId, nonRequester),
            nonRequester,
            resultHash
        );

        vm.prank(requester);
        acceptanceRegistry.acceptTaskResult(taskId, resultHash);

        expectedAcceptances[taskId] = ExpectedAcceptanceRecord({
            acceptedBy: requester, resultHash: resultHash, acceptedAt: uint64(block.timestamp)
        });

        _expectAcceptanceUnchanged(
            taskId,
            abi.encodeWithSelector(TaskAcceptanceRegistry.ResultAlreadyAccepted.selector, taskId, resultHash),
            requester,
            resultHash
        );
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

    function commitTaskResult(uint8 taskSeed, uint8 actorSeed, uint128 resultSeed) external {
        uint256 taskId = _taskId(taskSeed);
        ExpectedTaskIntent storage intentModel = expectedIntents[taskId];
        ExpectedResultRecord storage resultModel = expectedResults[taskId];
        address actor = _actor(actorSeed);
        bytes32 resultHash = _nonZeroHash("result", resultSeed);

        if (resultModel.resultHash != bytes32(0)) {
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

        address assignedOwner = registry.ownerOf(intentModel.assignedAgentId);

        if (actor != assignedOwner) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    TaskResultRegistry.NotAssignedAgentOwner.selector, taskId, intentModel.assignedAgentId, actor
                )
            );
            vm.prank(actor);
            resultRegistry.commitTaskResult(taskId, resultHash);
            return;
        }

        vm.prank(actor);
        resultRegistry.commitTaskResult(taskId, resultHash);

        resultModel.agentId = intentModel.assignedAgentId;
        resultModel.resultHash = resultHash;
        resultModel.submittedAt = uint64(block.timestamp);
    }

    function acceptTaskResult(uint8 taskSeed, uint8 actorSeed, uint128 resultSeed, uint8 mode) external {
        uint256 taskId = _taskId(taskSeed);
        ExpectedTaskIntent storage intentModel = expectedIntents[taskId];
        ExpectedResultRecord storage resultModel = expectedResults[taskId];
        ExpectedAcceptanceRecord storage acceptanceModel = expectedAcceptances[taskId];
        address actor = _actor(actorSeed);
        bytes32 resultHash = _acceptanceAttemptHash(resultModel.resultHash, resultSeed, mode);

        if (acceptanceModel.resultHash != bytes32(0)) {
            _expectAcceptanceUnchanged(
                taskId,
                abi.encodeWithSelector(
                    TaskAcceptanceRegistry.ResultAlreadyAccepted.selector, taskId, acceptanceModel.resultHash
                ),
                actor,
                resultHash
            );
            return;
        }

        if (intentModel.status != TaskIntentMarket.TaskStatus.Assigned) {
            _expectAcceptanceUnchanged(
                taskId,
                abi.encodeWithSelector(TaskAcceptanceRegistry.TaskNotAssigned.selector, taskId),
                actor,
                resultHash
            );
            return;
        }

        if (actor != intentModel.requester) {
            _expectAcceptanceUnchanged(
                taskId,
                abi.encodeWithSelector(TaskAcceptanceRegistry.NotTaskRequester.selector, taskId, actor),
                actor,
                resultHash
            );
            return;
        }

        if (resultModel.resultHash == bytes32(0)) {
            _expectAcceptanceUnchanged(
                taskId,
                abi.encodeWithSelector(TaskAcceptanceRegistry.ResultNotSubmitted.selector, taskId),
                actor,
                resultHash
            );
            return;
        }

        if (resultHash != resultModel.resultHash) {
            _expectAcceptanceUnchanged(
                taskId,
                abi.encodeWithSelector(
                    TaskAcceptanceRegistry.ResultHashMismatch.selector, taskId, resultModel.resultHash, resultHash
                ),
                actor,
                resultHash
            );
            return;
        }

        vm.prank(actor);
        acceptanceRegistry.acceptTaskResult(taskId, resultHash);

        acceptanceModel.acceptedBy = actor;
        acceptanceModel.resultHash = resultHash;
        acceptanceModel.acceptedAt = uint64(block.timestamp);
    }

    function probeRejectedAcceptanceAttempts() external {
        uint256 count = openedCount;

        for (uint256 taskId = 1; taskId <= count; taskId++) {
            ExpectedTaskIntent storage intentModel = expectedIntents[taskId];
            ExpectedResultRecord storage resultModel = expectedResults[taskId];
            ExpectedAcceptanceRecord storage acceptanceModel = expectedAcceptances[taskId];

            if (acceptanceModel.resultHash != bytes32(0)) {
                _expectAcceptanceUnchanged(
                    taskId,
                    abi.encodeWithSelector(
                        TaskAcceptanceRegistry.ResultAlreadyAccepted.selector, taskId, acceptanceModel.resultHash
                    ),
                    intentModel.requester,
                    acceptanceModel.resultHash
                );
                continue;
            }

            if (intentModel.status != TaskIntentMarket.TaskStatus.Assigned) {
                continue;
            }

            if (resultModel.resultHash == bytes32(0)) {
                bytes32 attemptedHash = _nonZeroHash("probe.unsubmitted", uint128(taskId));

                _expectAcceptanceUnchanged(
                    taskId,
                    abi.encodeWithSelector(TaskAcceptanceRegistry.ResultNotSubmitted.selector, taskId),
                    intentModel.requester,
                    attemptedHash
                );
                continue;
            }

            bytes32 wrongResultHash = _differentHash("probe.mismatch", uint128(taskId), resultModel.resultHash);

            _expectAcceptanceUnchanged(
                taskId,
                abi.encodeWithSelector(
                    TaskAcceptanceRegistry.ResultHashMismatch.selector, taskId, resultModel.resultHash, wrongResultHash
                ),
                intentModel.requester,
                wrongResultHash
            );
        }
    }

    function expectedIntent(uint256 taskId) external view returns (ExpectedTaskIntent memory) {
        return expectedIntents[taskId];
    }

    function expectedResult(uint256 taskId) external view returns (ExpectedResultRecord memory) {
        return expectedResults[taskId];
    }

    function expectedAcceptance(uint256 taskId) external view returns (ExpectedAcceptanceRecord memory) {
        return expectedAcceptances[taskId];
    }

    function agentCount() external pure returns (uint256) {
        return 3;
    }

    function _expectAcceptanceUnchanged(uint256 taskId, bytes memory revertData, address actor, bytes32 resultHash)
        internal
    {
        TaskAcceptanceRegistry.AcceptanceRecord memory beforeRecord = acceptanceRegistry.getAcceptanceRecord(taskId);

        vm.expectRevert(revertData);
        vm.prank(actor);
        acceptanceRegistry.acceptTaskResult(taskId, resultHash);

        TaskAcceptanceRegistry.AcceptanceRecord memory afterRecord = acceptanceRegistry.getAcceptanceRecord(taskId);

        assertEq(afterRecord.acceptedBy, beforeRecord.acceptedBy);
        assertEq(afterRecord.resultHash, beforeRecord.resultHash);
        assertEq(afterRecord.acceptedAt, beforeRecord.acceptedAt);
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

    function _otherActor(uint8 seed) internal view returns (address) {
        address actor = _actor(seed);

        for (uint256 i = 1; i <= 6; i++) {
            address candidate = _actor(uint8(uint256(seed) + i));

            if (candidate != actor) {
                return candidate;
            }
        }

        return address(0xBEEF);
    }

    function _acceptanceAttemptHash(bytes32 submittedResultHash, uint128 resultSeed, uint8 mode)
        internal
        pure
        returns (bytes32)
    {
        if (submittedResultHash != bytes32(0) && mode % 2 == 0) {
            return submittedResultHash;
        }

        return _nonZeroHash("accept.result", resultSeed);
    }

    function _nonZeroHash(string memory domain, uint128 seed) internal pure returns (bytes32 hash) {
        hash = keccak256(abi.encode(domain, seed));

        if (hash == bytes32(0)) {
            return keccak256(abi.encode(domain, uint256(1)));
        }
    }

    function _differentHash(string memory domain, uint128 seed, bytes32 forbidden)
        internal
        pure
        returns (bytes32 hash)
    {
        hash = _nonZeroHash(domain, seed);

        if (hash == forbidden) {
            uint128 nextSeed = seed == type(uint128).max ? 0 : seed + 1;

            return _nonZeroHash(domain, nextSeed);
        }
    }
}

contract TaskAcceptanceRegistryStatefulFuzzTest is Test {
    AgentRegistry internal registry;
    MockAcceptanceTaskAuthorizationGate internal gate;
    PolicyRootChain internal rootChain;
    TaskIntentMarket internal market;
    TaskResultRegistry internal resultRegistry;
    TaskAcceptanceRegistry internal acceptanceRegistry;
    TaskAcceptanceRegistryHandler internal handler;

    function setUp() public {
        rootChain = new PolicyRootChain();
        registry = new AgentRegistry(address(rootChain));
        gate = new MockAcceptanceTaskAuthorizationGate();
        market = new TaskIntentMarket(address(registry), address(gate));
        resultRegistry = new TaskResultRegistry(address(registry), address(market));
        acceptanceRegistry = new TaskAcceptanceRegistry(address(market), address(resultRegistry));
        handler = new TaskAcceptanceRegistryHandler(registry, gate, market, resultRegistry, acceptanceRegistry);

        uint256 count = handler.agentCount();

        for (uint256 i = 0; i < count; i++) {
            bytes32 agentId = handler.agentIds(i);
            address owner = handler.agentOwners(i);
            bytes32 root = keccak256(abi.encode("task.acceptance.invariant.root", agentId));

            vm.prank(owner);
            registry.registerAgent(agentId, root);
            gate.setAuthorizedAgent(agentId, true);
        }
    }

    function testFuzz_TaskAcceptanceStateMatchesModelAcrossOperationSequence(uint256 seed) public {
        handler.seedAcceptedTaskWithRejectedAcceptanceAttempts(
            uint8(seed), uint8(seed >> 8), uint128(uint256(keccak256(abi.encode(seed, "seed.result"))))
        );

        for (uint256 i = 0; i < 64; i++) {
            uint256 step = uint256(keccak256(abi.encode(seed, i)));
            uint8 operation = uint8(step);

            if (operation % 4 == 0) {
                handler.openTaskIntent(uint8(step >> 8), uint128(step >> 16), uint128(step >> 144));
            } else if (operation % 4 == 1) {
                handler.claimTaskIntent(uint8(step >> 8), uint8(step >> 16), uint8(step >> 24));
            } else if (operation % 4 == 2) {
                handler.commitTaskResult(uint8(step >> 8), uint8(step >> 16), uint128(step >> 24));
            } else {
                handler.acceptTaskResult(uint8(step >> 8), uint8(step >> 16), uint128(step >> 24), uint8(step >> 152));
            }
        }

        handler.probeRejectedAcceptanceAttempts();

        _assertNextTaskIdTracksOpenedTaskCount();
        _assertTaskStateMatchesModel();
        _assertResultStateMatchesModel();
        _assertAcceptanceStateMatchesModel();
        _assertRequesterOnlyAcceptance();
        _assertAcceptedRecordsAreTerminal();
    }

    function _assertNextTaskIdTracksOpenedTaskCount() internal view {
        assertEq(market.nextTaskId(), handler.openedCount() + 1);
    }

    function _assertTaskStateMatchesModel() internal view {
        uint256 openedCount = handler.openedCount();

        for (uint256 taskId = 1; taskId <= openedCount; taskId++) {
            TaskIntentMarket.TaskIntent memory actual = market.getTaskIntent(taskId);
            TaskAcceptanceRegistryHandler.ExpectedTaskIntent memory expected = handler.expectedIntent(taskId);

            assertEq(actual.requester, expected.requester);
            assertEq(actual.actionHash, expected.actionHash);
            assertEq(actual.taskDataHash, expected.taskDataHash);
            assertEq(actual.assignedAgentId, expected.assignedAgentId);
            assertEq(actual.createdAt, expected.createdAt);
            assertEq(actual.assignedAt, expected.assignedAt);
            assertEq(uint8(actual.status), uint8(expected.status));
        }
    }

    function _assertResultStateMatchesModel() internal view {
        uint256 openedCount = handler.openedCount();

        for (uint256 taskId = 1; taskId <= openedCount; taskId++) {
            TaskResultRegistry.ResultRecord memory actual = resultRegistry.getResultRecord(taskId);
            TaskAcceptanceRegistryHandler.ExpectedResultRecord memory expected = handler.expectedResult(taskId);

            assertEq(actual.agentId, expected.agentId);
            assertEq(actual.resultHash, expected.resultHash);
            assertEq(actual.submittedAt, expected.submittedAt);
        }
    }

    function _assertAcceptanceStateMatchesModel() internal view {
        uint256 openedCount = handler.openedCount();

        for (uint256 taskId = 1; taskId <= openedCount; taskId++) {
            TaskAcceptanceRegistry.AcceptanceRecord memory actual = acceptanceRegistry.getAcceptanceRecord(taskId);
            TaskAcceptanceRegistryHandler.ExpectedAcceptanceRecord memory expected = handler.expectedAcceptance(taskId);

            assertEq(actual.acceptedBy, expected.acceptedBy);
            assertEq(actual.resultHash, expected.resultHash);
            assertEq(actual.acceptedAt, expected.acceptedAt);
        }
    }

    function _assertRequesterOnlyAcceptance() internal view {
        uint256 openedCount = handler.openedCount();

        for (uint256 taskId = 1; taskId <= openedCount; taskId++) {
            TaskAcceptanceRegistry.AcceptanceRecord memory acceptance = acceptanceRegistry.getAcceptanceRecord(taskId);

            if (acceptance.resultHash == bytes32(0)) {
                assertEq(acceptance.acceptedBy, address(0));
                assertEq(acceptance.acceptedAt, 0);
                continue;
            }

            TaskAcceptanceRegistryHandler.ExpectedTaskIntent memory intent = handler.expectedIntent(taskId);

            assertEq(acceptance.acceptedBy, intent.requester);
        }
    }

    function _assertAcceptedRecordsAreTerminal() internal view {
        uint256 openedCount = handler.openedCount();

        for (uint256 taskId = 1; taskId <= openedCount; taskId++) {
            TaskAcceptanceRegistry.AcceptanceRecord memory acceptance = acceptanceRegistry.getAcceptanceRecord(taskId);

            if (acceptance.resultHash == bytes32(0)) {
                continue;
            }

            TaskResultRegistry.ResultRecord memory result = resultRegistry.getResultRecord(taskId);
            TaskAcceptanceRegistryHandler.ExpectedAcceptanceRecord memory expected = handler.expectedAcceptance(taskId);

            assertEq(acceptance.resultHash, result.resultHash);
            assertEq(acceptance.resultHash, expected.resultHash);
            assertEq(acceptance.acceptedBy, expected.acceptedBy);
            assertEq(acceptance.acceptedAt, expected.acceptedAt);
            assertGe(acceptance.acceptedAt, result.submittedAt);
        }
    }
}
