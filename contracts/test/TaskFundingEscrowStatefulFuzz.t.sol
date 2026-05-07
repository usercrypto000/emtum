// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {PolicyRootChain} from "../src/PolicyRootChain.sol";
import {TaskAcceptanceRegistry} from "../src/TaskAcceptanceRegistry.sol";
import {TaskFundingEscrow} from "../src/TaskFundingEscrow.sol";
import {TaskIntentMarket} from "../src/TaskIntentMarket.sol";
import {TaskResultRegistry} from "../src/TaskResultRegistry.sol";

contract MockEscrowAuthorizationGate {
    function isTaskAuthorized(bytes32, bytes calldata, bytes32) external pure returns (bool) {
        return true;
    }
}

contract TaskFundingEscrowHandler is Test {
    uint256 internal constant ACTOR_COUNT = 6;
    uint256 internal constant INITIAL_BALANCE = 1_000 ether;
    uint256 internal constant MAX_FUNDING_AMOUNT = 5 ether;
    uint256 internal constant MAX_TRACKED_TASKS = 32;

    struct ExpectedTaskFunding {
        address requester;
        TaskIntentMarket.TaskStatus taskStatus;
        address payer;
        uint256 amount;
        TaskFundingEscrow.EscrowStatus escrowStatus;
    }

    TaskIntentMarket public immutable market;
    TaskFundingEscrow public immutable escrow;

    uint256 public expectedEscrowBalance;
    uint256 public openedCount;

    address[ACTOR_COUNT] public actors;

    mapping(uint256 taskId => ExpectedTaskFunding funding) internal expectedFundings;
    mapping(address actor => uint256 balance) internal expectedBalances;

    constructor(TaskIntentMarket market_, TaskFundingEscrow escrow_) {
        market = market_;
        escrow = escrow_;

        actors[0] = address(0xA11CE);
        actors[1] = address(0xB0B);
        actors[2] = address(0xCA11);
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
            _nonZeroHash("escrow.action", actionSeed), _nonZeroHash("escrow.task.data", dataSeed)
        );

        openedCount += 1;

        assertEq(taskId, openedCount);

        expectedFundings[taskId] = ExpectedTaskFunding({
            requester: requester,
            taskStatus: TaskIntentMarket.TaskStatus.Open,
            payer: address(0),
            amount: 0,
            escrowStatus: TaskFundingEscrow.EscrowStatus.None
        });
    }

    function fundTaskIntent(uint8 taskSeed, uint8 actorSeed, uint128 amountSeed) external {
        uint256 taskId = _taskId(taskSeed);
        ExpectedTaskFunding storage expected = expectedFundings[taskId];
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

    function cancelTaskIntent(uint8 taskSeed, uint8 actorSeed) external {
        uint256 taskId = _taskId(taskSeed);
        ExpectedTaskFunding storage expected = expectedFundings[taskId];
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
        ExpectedTaskFunding storage expected = expectedFundings[taskId];
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

    function expectedFunding(uint256 taskId) external view returns (ExpectedTaskFunding memory) {
        return expectedFundings[taskId];
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

contract TaskFundingEscrowStatefulFuzzTest is Test {
    AgentRegistry internal registry;
    MockEscrowAuthorizationGate internal gate;
    PolicyRootChain internal rootChain;
    TaskAcceptanceRegistry internal acceptanceRegistry;
    TaskIntentMarket internal market;
    TaskResultRegistry internal resultRegistry;
    TaskFundingEscrow internal escrow;
    TaskFundingEscrowHandler internal handler;

    function setUp() public {
        rootChain = new PolicyRootChain();
        registry = new AgentRegistry(address(rootChain));
        gate = new MockEscrowAuthorizationGate();
        market = new TaskIntentMarket(address(registry), address(gate));
        resultRegistry = new TaskResultRegistry(address(registry), address(market));
        acceptanceRegistry = new TaskAcceptanceRegistry(address(market), address(resultRegistry));
        escrow = new TaskFundingEscrow(address(registry), address(market), address(acceptanceRegistry));
        handler = new TaskFundingEscrowHandler(market, escrow);

        uint256 count = handler.actorCount();

        for (uint256 i = 0; i < count; i++) {
            vm.deal(handler.actors(i), handler.initialBalance());
        }
    }

    function testFuzz_TaskFundingEscrowStateMatchesModelAcrossOperationSequence(uint256 seed) public {
        for (uint256 i = 0; i < 64; i++) {
            uint256 step = uint256(keccak256(abi.encode(seed, i)));
            uint8 operation = uint8(step);

            if (operation % 4 == 0) {
                handler.openTaskIntent(uint8(step >> 8), uint128(step >> 16), uint128(step >> 144));
            } else if (operation % 4 == 1) {
                handler.fundTaskIntent(uint8(step >> 8), uint8(step >> 16), uint128(step >> 24));
            } else if (operation % 4 == 2) {
                handler.cancelTaskIntent(uint8(step >> 8), uint8(step >> 16));
            } else {
                handler.refundCancelledTaskIntent(uint8(step >> 8), uint8(step >> 16));
            }
        }

        _assertNextTaskIdTracksOpenedTaskCount();
        _assertTaskStatusesMatchModel();
        _assertEscrowRecordsMatchModel();
        _assertBalancesMatchModel();
        _assertEscrowStatusRemainsConsistent();
    }

    function _assertNextTaskIdTracksOpenedTaskCount() internal view {
        assertEq(market.nextTaskId(), handler.openedCount() + 1);
    }

    function _assertTaskStatusesMatchModel() internal view {
        uint256 openedCount = handler.openedCount();

        for (uint256 taskId = 1; taskId <= openedCount; taskId++) {
            TaskIntentMarket.TaskIntent memory actual = market.getTaskIntent(taskId);
            TaskFundingEscrowHandler.ExpectedTaskFunding memory expected = handler.expectedFunding(taskId);

            assertEq(actual.requester, expected.requester);
            assertEq(uint8(actual.status), uint8(expected.taskStatus));
        }
    }

    function _assertEscrowRecordsMatchModel() internal view {
        uint256 openedCount = handler.openedCount();

        for (uint256 taskId = 1; taskId <= openedCount; taskId++) {
            TaskFundingEscrow.EscrowRecord memory actual = escrow.getEscrowRecord(taskId);
            TaskFundingEscrowHandler.ExpectedTaskFunding memory expected = handler.expectedFunding(taskId);

            assertEq(actual.payer, expected.payer);
            assertEq(actual.amount, expected.amount);
            assertEq(uint8(actual.status), uint8(expected.escrowStatus));
        }
    }

    function _assertBalancesMatchModel() internal view {
        assertEq(address(escrow).balance, handler.expectedEscrowBalance());

        uint256 count = handler.actorCount();

        for (uint256 i = 0; i < count; i++) {
            address actor = handler.actors(i);

            assertEq(actor.balance, handler.expectedBalance(actor));
        }
    }

    function _assertEscrowStatusRemainsConsistent() internal view {
        uint256 openedCount = handler.openedCount();
        uint256 fundedBalance;

        for (uint256 taskId = 1; taskId <= openedCount; taskId++) {
            TaskFundingEscrow.EscrowRecord memory record = escrow.getEscrowRecord(taskId);
            TaskFundingEscrowHandler.ExpectedTaskFunding memory expected = handler.expectedFunding(taskId);

            if (record.status == TaskFundingEscrow.EscrowStatus.None) {
                assertEq(record.payer, address(0));
                assertEq(record.amount, 0);
                continue;
            }

            assertEq(record.payer, expected.requester);
            assertGt(record.amount, 0);

            if (record.status == TaskFundingEscrow.EscrowStatus.Funded) {
                fundedBalance += record.amount;
                continue;
            }

            if (record.status == TaskFundingEscrow.EscrowStatus.Refunded) {
                assertEq(uint8(expected.taskStatus), uint8(TaskIntentMarket.TaskStatus.Cancelled));
                continue;
            }

            revert("unexpected escrow status");
        }

        assertEq(fundedBalance, address(escrow).balance);
    }
}
