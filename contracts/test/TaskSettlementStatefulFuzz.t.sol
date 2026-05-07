// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {PolicyRootChain} from "../src/PolicyRootChain.sol";
import {TaskAcceptanceRegistry} from "../src/TaskAcceptanceRegistry.sol";
import {TaskFundingEscrow} from "../src/TaskFundingEscrow.sol";
import {TaskIntentMarket} from "../src/TaskIntentMarket.sol";
import {TaskResultRegistry} from "../src/TaskResultRegistry.sol";

contract MockSettlementAuthorizationGate {
    function isTaskAuthorized(bytes32, bytes calldata, bytes32) external pure returns (bool) {
        return true;
    }
}

contract TaskSettlementHandler is Test {
    uint256 internal constant ACTOR_COUNT = 6;
    uint256 internal constant INITIAL_BALANCE = 1_000 ether;
    uint256 internal constant MAX_FUNDING_AMOUNT = 5 ether;
    uint256 internal constant MAX_TRACKED_TASKS = 24;

    struct ExpectedSettlement {
        address requester;
        bytes32 assignedAgentId;
        address assignedAgentOwner;
        TaskIntentMarket.TaskStatus taskStatus;
        address payer;
        uint256 amount;
        TaskFundingEscrow.EscrowStatus escrowStatus;
        bytes32 resultHash;
        bytes32 acceptanceHash;
    }

    AgentRegistry public immutable registry;
    TaskIntentMarket public immutable market;
    TaskResultRegistry public immutable resultRegistry;
    TaskAcceptanceRegistry public immutable acceptanceRegistry;
    TaskFundingEscrow public immutable escrow;

    bytes32[3] public agentIds;
    address[3] public agentOwners;
    address[ACTOR_COUNT] public actors;

    uint256 public expectedEscrowBalance;
    uint256 public openedCount;

    mapping(uint256 taskId => ExpectedSettlement settlement) internal expectedSettlements;
    mapping(address actor => uint256 balance) internal expectedBalances;

    constructor(
        AgentRegistry registry_,
        TaskIntentMarket market_,
        TaskResultRegistry resultRegistry_,
        TaskAcceptanceRegistry acceptanceRegistry_,
        TaskFundingEscrow escrow_
    ) {
        registry = registry_;
        market = market_;
        resultRegistry = resultRegistry_;
        acceptanceRegistry = acceptanceRegistry_;
        escrow = escrow_;

        agentIds[0] = keccak256("emtun.settlement.agent.alpha");
        agentIds[1] = keccak256("emtun.settlement.agent.beta");
        agentIds[2] = keccak256("emtun.settlement.agent.gamma");

        agentOwners[0] = address(0xA11CE);
        agentOwners[1] = address(0xB0B);
        agentOwners[2] = address(0xCA11);

        actors[0] = agentOwners[0];
        actors[1] = agentOwners[1];
        actors[2] = agentOwners[2];
        actors[3] = address(0xD00D);
        actors[4] = address(0xE77A);
        actors[5] = address(0xF00D);

        for (uint256 i = 0; i < ACTOR_COUNT; i++) {
            expectedBalances[actors[i]] = INITIAL_BALANCE;
        }
    }

    function openTaskIntent(uint8 requesterSeed, uint128 actionSeed, uint128 dataSeed) external {
        if (openedCount >= MAX_TRACKED_TASKS) {
            return;
        }

        address requester = _actor(requesterSeed);

        vm.prank(requester);
        uint256 taskId = market.openTaskIntent(
            _nonZeroHash("settlement.action", actionSeed), _nonZeroHash("settlement.task.data", dataSeed)
        );

        openedCount += 1;
        assertEq(taskId, openedCount);

        expectedSettlements[taskId] = ExpectedSettlement({
            requester: requester,
            assignedAgentId: bytes32(0),
            assignedAgentOwner: address(0),
            taskStatus: TaskIntentMarket.TaskStatus.Open,
            payer: address(0),
            amount: 0,
            escrowStatus: TaskFundingEscrow.EscrowStatus.None,
            resultHash: bytes32(0),
            acceptanceHash: bytes32(0)
        });
    }

    function fundTaskIntent(uint8 taskSeed, uint8 actorSeed, uint128 amountSeed) external {
        uint256 taskId = _taskId(taskSeed);
        ExpectedSettlement storage expected = expectedSettlements[taskId];
        address actor = _actor(actorSeed);
        uint256 amount = _fundingAmount(amountSeed);

        if (expected.taskStatus != TaskIntentMarket.TaskStatus.Open) {
            vm.expectRevert(abi.encodeWithSelector(TaskFundingEscrow.TaskNotOpen.selector, taskId));
            vm.prank(actor);
            escrow.fundTaskIntent{value: amount}(taskId);
            return;
        }

        if (actor != expected.requester) {
            vm.expectRevert(abi.encodeWithSelector(TaskFundingEscrow.NotTaskRequester.selector, taskId, actor));
            vm.prank(actor);
            escrow.fundTaskIntent{value: amount}(taskId);
            return;
        }

        if (expected.escrowStatus != TaskFundingEscrow.EscrowStatus.None) {
            vm.expectRevert(abi.encodeWithSelector(TaskFundingEscrow.EscrowAlreadyFunded.selector, taskId));
            vm.prank(actor);
            escrow.fundTaskIntent{value: amount}(taskId);
            return;
        }

        vm.prank(actor);
        escrow.fundTaskIntent{value: amount}(taskId);

        expected.payer = actor;
        expected.amount = amount;
        expected.escrowStatus = TaskFundingEscrow.EscrowStatus.Funded;
        expectedBalances[actor] -= amount;
        expectedEscrowBalance += amount;
    }

    function claimTaskIntent(uint8 taskSeed, uint8 agentSeed, uint8 actorSeed) external {
        uint256 taskId = _taskId(taskSeed);
        ExpectedSettlement storage expected = expectedSettlements[taskId];
        bytes32 agentId = _agentId(agentSeed);
        address owner = _agentOwner(agentSeed);
        address actor = _actor(actorSeed);

        if (expected.taskStatus != TaskIntentMarket.TaskStatus.Open) {
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
        expected.assignedAgentOwner = owner;
        expected.taskStatus = TaskIntentMarket.TaskStatus.Assigned;
    }

    function cancelTaskIntent(uint8 taskSeed, uint8 actorSeed) external {
        uint256 taskId = _taskId(taskSeed);
        ExpectedSettlement storage expected = expectedSettlements[taskId];
        address actor = _actor(actorSeed);

        if (expected.taskStatus != TaskIntentMarket.TaskStatus.Open) {
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

        expected.taskStatus = TaskIntentMarket.TaskStatus.Cancelled;
    }

    function refundCancelledTaskIntent(uint8 taskSeed, uint8 actorSeed) external {
        uint256 taskId = _taskId(taskSeed);
        ExpectedSettlement storage expected = expectedSettlements[taskId];
        address actor = _actor(actorSeed);

        if (expected.escrowStatus != TaskFundingEscrow.EscrowStatus.Funded) {
            vm.expectRevert(abi.encodeWithSelector(TaskFundingEscrow.EscrowNotFunded.selector, taskId));
            vm.prank(actor);
            escrow.refundCancelledTaskIntent(taskId);
            return;
        }

        if (expected.taskStatus != TaskIntentMarket.TaskStatus.Cancelled) {
            vm.expectRevert(abi.encodeWithSelector(TaskFundingEscrow.TaskNotCancelled.selector, taskId));
            vm.prank(actor);
            escrow.refundCancelledTaskIntent(taskId);
            return;
        }

        if (actor != expected.payer) {
            vm.expectRevert(abi.encodeWithSelector(TaskFundingEscrow.NotEscrowPayer.selector, taskId, actor));
            vm.prank(actor);
            escrow.refundCancelledTaskIntent(taskId);
            return;
        }

        vm.prank(actor);
        escrow.refundCancelledTaskIntent(taskId);

        expected.escrowStatus = TaskFundingEscrow.EscrowStatus.Refunded;
        expectedBalances[actor] += expected.amount;
        expectedEscrowBalance -= expected.amount;
    }

    function commitTaskResult(uint8 taskSeed, uint8 actorSeed, uint128 resultSeed) external {
        uint256 taskId = _taskId(taskSeed);
        ExpectedSettlement storage expected = expectedSettlements[taskId];
        address actor = _actor(actorSeed);
        bytes32 resultHash = _nonZeroHash("settlement.result", resultSeed);

        if (expected.resultHash != bytes32(0)) {
            vm.expectRevert(
                abi.encodeWithSelector(TaskResultRegistry.ResultAlreadySubmitted.selector, taskId, expected.resultHash)
            );
            vm.prank(actor);
            resultRegistry.commitTaskResult(taskId, resultHash);
            return;
        }

        if (expected.taskStatus != TaskIntentMarket.TaskStatus.Assigned) {
            vm.expectRevert(abi.encodeWithSelector(TaskResultRegistry.TaskNotAssigned.selector, taskId));
            vm.prank(actor);
            resultRegistry.commitTaskResult(taskId, resultHash);
            return;
        }

        if (actor != expected.assignedAgentOwner) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    TaskResultRegistry.NotAssignedAgentOwner.selector, taskId, expected.assignedAgentId, actor
                )
            );
            vm.prank(actor);
            resultRegistry.commitTaskResult(taskId, resultHash);
            return;
        }

        vm.prank(actor);
        resultRegistry.commitTaskResult(taskId, resultHash);

        expected.resultHash = resultHash;
    }

    function acceptTaskResult(uint8 taskSeed, uint8 actorSeed, uint8 mode, uint128 resultSeed) external {
        uint256 taskId = _taskId(taskSeed);
        ExpectedSettlement storage expected = expectedSettlements[taskId];
        address actor = _actor(actorSeed);
        bytes32 resultHash = mode % 2 == 0 && expected.resultHash != bytes32(0)
            ? expected.resultHash
            : _nonZeroHash("settlement.acceptance", resultSeed);

        if (expected.acceptanceHash != bytes32(0)) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    TaskAcceptanceRegistry.ResultAlreadyAccepted.selector, taskId, expected.acceptanceHash
                )
            );
            vm.prank(actor);
            acceptanceRegistry.acceptTaskResult(taskId, resultHash);
            return;
        }

        if (expected.taskStatus != TaskIntentMarket.TaskStatus.Assigned) {
            vm.expectRevert(abi.encodeWithSelector(TaskAcceptanceRegistry.TaskNotAssigned.selector, taskId));
            vm.prank(actor);
            acceptanceRegistry.acceptTaskResult(taskId, resultHash);
            return;
        }

        if (actor != expected.requester) {
            vm.expectRevert(abi.encodeWithSelector(TaskAcceptanceRegistry.NotTaskRequester.selector, taskId, actor));
            vm.prank(actor);
            acceptanceRegistry.acceptTaskResult(taskId, resultHash);
            return;
        }

        if (expected.resultHash == bytes32(0)) {
            vm.expectRevert(abi.encodeWithSelector(TaskAcceptanceRegistry.ResultNotSubmitted.selector, taskId));
            vm.prank(actor);
            acceptanceRegistry.acceptTaskResult(taskId, resultHash);
            return;
        }

        if (resultHash != expected.resultHash) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    TaskAcceptanceRegistry.ResultHashMismatch.selector, taskId, expected.resultHash, resultHash
                )
            );
            vm.prank(actor);
            acceptanceRegistry.acceptTaskResult(taskId, resultHash);
            return;
        }

        vm.prank(actor);
        acceptanceRegistry.acceptTaskResult(taskId, resultHash);

        expected.acceptanceHash = resultHash;
    }

    function releaseAcceptedTaskIntent(uint8 taskSeed) external {
        uint256 taskId = _taskId(taskSeed);
        ExpectedSettlement storage expected = expectedSettlements[taskId];

        if (expected.escrowStatus != TaskFundingEscrow.EscrowStatus.Funded) {
            vm.expectRevert(abi.encodeWithSelector(TaskFundingEscrow.EscrowNotFunded.selector, taskId));
            escrow.releaseAcceptedTaskIntent(taskId);
            return;
        }

        if (expected.taskStatus != TaskIntentMarket.TaskStatus.Assigned) {
            vm.expectRevert(abi.encodeWithSelector(TaskFundingEscrow.TaskNotAssigned.selector, taskId));
            escrow.releaseAcceptedTaskIntent(taskId);
            return;
        }

        if (expected.acceptanceHash == bytes32(0)) {
            vm.expectRevert(abi.encodeWithSelector(TaskFundingEscrow.TaskResultNotAccepted.selector, taskId));
            escrow.releaseAcceptedTaskIntent(taskId);
            return;
        }

        escrow.releaseAcceptedTaskIntent(taskId);

        expected.escrowStatus = TaskFundingEscrow.EscrowStatus.Released;
        expectedBalances[expected.assignedAgentOwner] += expected.amount;
        expectedEscrowBalance -= expected.amount;
    }

    function expectedSettlement(uint256 taskId) external view returns (ExpectedSettlement memory) {
        return expectedSettlements[taskId];
    }

    function expectedBalance(address actor) external view returns (uint256) {
        return expectedBalances[actor];
    }

    function actorCount() external pure returns (uint256) {
        return ACTOR_COUNT;
    }

    function initialBalance() external pure returns (uint256) {
        return INITIAL_BALANCE;
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

    function _actor(uint8 seed) internal view returns (address) {
        return actors[uint256(seed) % ACTOR_COUNT];
    }

    function _agentId(uint8 seed) internal view returns (bytes32) {
        return agentIds[uint256(seed) % agentIds.length];
    }

    function _agentOwner(uint8 seed) internal view returns (address) {
        return agentOwners[uint256(seed) % agentOwners.length];
    }

    function _fundingAmount(uint128 seed) internal pure returns (uint256) {
        return (uint256(seed) % MAX_FUNDING_AMOUNT) + 1;
    }

    function _nonZeroHash(string memory domain, uint128 seed) internal pure returns (bytes32 hash) {
        hash = keccak256(abi.encode(domain, seed));

        if (hash == bytes32(0)) {
            return keccak256(abi.encode(domain, uint256(1)));
        }
    }
}

contract TaskSettlementStatefulFuzzTest is Test {
    AgentRegistry internal registry;
    MockSettlementAuthorizationGate internal gate;
    PolicyRootChain internal rootChain;
    TaskIntentMarket internal market;
    TaskResultRegistry internal resultRegistry;
    TaskAcceptanceRegistry internal acceptanceRegistry;
    TaskFundingEscrow internal escrow;
    TaskSettlementHandler internal handler;

    function setUp() public {
        rootChain = new PolicyRootChain();
        registry = new AgentRegistry(address(rootChain));
        gate = new MockSettlementAuthorizationGate();
        market = new TaskIntentMarket(address(registry), address(gate));
        resultRegistry = new TaskResultRegistry(address(registry), address(market));
        acceptanceRegistry = new TaskAcceptanceRegistry(address(market), address(resultRegistry));
        escrow = new TaskFundingEscrow(address(registry), address(market), address(acceptanceRegistry));
        handler = new TaskSettlementHandler(registry, market, resultRegistry, acceptanceRegistry, escrow);

        uint256 actorCount = handler.actorCount();

        for (uint256 i = 0; i < actorCount; i++) {
            vm.deal(handler.actors(i), handler.initialBalance());
        }

        uint256 agentCount = handler.agentCount();

        for (uint256 i = 0; i < agentCount; i++) {
            bytes32 agentId = handler.agentIds(i);
            address owner = handler.agentOwners(i);
            bytes32 root = keccak256(abi.encode("task.settlement.invariant.root", agentId));

            vm.prank(owner);
            registry.registerAgent(agentId, root);
        }
    }

    function testFuzz_TaskSettlementStateMatchesModelAcrossOperationSequence(uint256 seed) public {
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

        _assertNextTaskIdTracksOpenedTaskCount();
        _assertSettlementStateMatchesModel();
        _assertBalancesMatchModel();
        _assertReleasedEscrowsHaveAcceptedResults();
    }

    function _assertNextTaskIdTracksOpenedTaskCount() internal view {
        assertEq(market.nextTaskId(), handler.openedCount() + 1);
    }

    function _assertSettlementStateMatchesModel() internal view {
        uint256 openedCount = handler.openedCount();

        for (uint256 taskId = 1; taskId <= openedCount; taskId++) {
            TaskSettlementHandler.ExpectedSettlement memory expected = handler.expectedSettlement(taskId);
            TaskIntentMarket.TaskIntent memory actualIntent = market.getTaskIntent(taskId);
            TaskFundingEscrow.EscrowRecord memory actualEscrow = escrow.getEscrowRecord(taskId);
            TaskResultRegistry.ResultRecord memory actualResult = resultRegistry.getResultRecord(taskId);
            TaskAcceptanceRegistry.AcceptanceRecord memory actualAcceptance =
                acceptanceRegistry.getAcceptanceRecord(taskId);

            assertEq(actualIntent.requester, expected.requester);
            assertEq(actualIntent.assignedAgentId, expected.assignedAgentId);
            assertEq(uint8(actualIntent.status), uint8(expected.taskStatus));
            assertEq(actualEscrow.payer, expected.payer);
            assertEq(actualEscrow.amount, expected.amount);
            assertEq(uint8(actualEscrow.status), uint8(expected.escrowStatus));
            assertEq(actualResult.resultHash, expected.resultHash);
            assertEq(actualAcceptance.resultHash, expected.acceptanceHash);
        }
    }

    function _assertBalancesMatchModel() internal view {
        assertEq(address(escrow).balance, handler.expectedEscrowBalance());

        uint256 actorCount = handler.actorCount();

        for (uint256 i = 0; i < actorCount; i++) {
            address actor = handler.actors(i);

            assertEq(actor.balance, handler.expectedBalance(actor));
        }
    }

    function _assertReleasedEscrowsHaveAcceptedResults() internal view {
        uint256 openedCount = handler.openedCount();

        for (uint256 taskId = 1; taskId <= openedCount; taskId++) {
            TaskFundingEscrow.EscrowRecord memory escrowRecord = escrow.getEscrowRecord(taskId);

            if (escrowRecord.status != TaskFundingEscrow.EscrowStatus.Released) {
                continue;
            }

            TaskAcceptanceRegistry.AcceptanceRecord memory acceptance = acceptanceRegistry.getAcceptanceRecord(taskId);
            TaskResultRegistry.ResultRecord memory result = resultRegistry.getResultRecord(taskId);

            assertTrue(acceptance.resultHash != bytes32(0));
            assertEq(acceptance.resultHash, result.resultHash);
        }
    }
}
