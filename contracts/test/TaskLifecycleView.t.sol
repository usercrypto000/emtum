// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {EmtunAuthorizationReader} from "../src/EmtunAuthorizationReader.sol";
import {EmtunEASAttestationBoundary} from "../src/EmtunEASAttestationBoundary.sol";
import {EmtunVerifierAdapter} from "../src/EmtunVerifierAdapter.sol";
import {MockEAS} from "../src/MockEAS.sol";
import {PolicyRootChain} from "../src/PolicyRootChain.sol";
import {TaskAcceptanceRegistry} from "../src/TaskAcceptanceRegistry.sol";
import {TaskAuthorizationGate} from "../src/TaskAuthorizationGate.sol";
import {TaskFundingEscrow} from "../src/TaskFundingEscrow.sol";
import {TaskIntentMarket} from "../src/TaskIntentMarket.sol";
import {TaskLifecycleView} from "../src/TaskLifecycleView.sol";
import {TaskResultRegistry} from "../src/TaskResultRegistry.sol";
import {HonkVerifier} from "../src/verifiers/EmtunPolicyVerifier.sol";
import {MerkleInclusionFixture} from "./fixtures/MerkleInclusionFixture.sol";

contract TaskLifecycleViewTest is Test {
    AgentRegistry internal registry;
    EmtunEASAttestationBoundary internal boundary;
    MockEAS internal eas;
    PolicyRootChain internal rootChain;
    TaskAuthorizationGate internal gate;
    TaskIntentMarket internal market;
    TaskFundingEscrow internal escrow;
    TaskResultRegistry internal resultRegistry;
    TaskAcceptanceRegistry internal acceptanceRegistry;
    TaskLifecycleView internal lifecycleView;

    bytes32 internal constant AGENT_ID = keccak256("emtun.agent.alpha");
    bytes32 internal constant TASK_DATA_HASH = keccak256("task.intent.payload");
    bytes32 internal constant RESULT_HASH = keccak256("task.result.payload");
    uint256 internal constant FUNDING_AMOUNT = 1 ether;

    address internal owner = address(0xA11CE);
    address internal requester = address(0xCAFE);

    function setUp() public {
        rootChain = new PolicyRootChain();
        HonkVerifier honkVerifier = new HonkVerifier();
        EmtunVerifierAdapter adapter = new EmtunVerifierAdapter(address(honkVerifier));
        EmtunAuthorizationReader reader = new EmtunAuthorizationReader(address(rootChain), address(adapter));

        registry = new AgentRegistry(address(rootChain));
        eas = new MockEAS();
        boundary = new EmtunEASAttestationBoundary(address(registry), address(eas));
        gate = new TaskAuthorizationGate(address(registry), address(boundary), address(reader));
        market = new TaskIntentMarket(address(registry), address(gate));
        resultRegistry = new TaskResultRegistry(address(registry), address(market));
        acceptanceRegistry = new TaskAcceptanceRegistry(address(market), address(resultRegistry));
        escrow = new TaskFundingEscrow(address(registry), address(market), address(acceptanceRegistry));
        lifecycleView = new TaskLifecycleView(
            address(market), address(escrow), address(resultRegistry), address(acceptanceRegistry)
        );

        vm.deal(requester, 10 ether);
    }

    function test_ReadsEmptyTaskLifecycle() public view {
        TaskLifecycleView.TaskLifecycle memory lifecycle = lifecycleView.getTaskLifecycle(999);

        _assertLifecycle(
            lifecycle,
            TaskIntentMarket.TaskStatus.None,
            TaskFundingEscrow.EscrowStatus.None,
            bytes32(0),
            bytes32(0),
            address(0),
            bytes32(0),
            0
        );
    }

    function test_ReadsOpenTaskLifecycle() public {
        uint256 taskId = _openTaskIntent();

        TaskLifecycleView.TaskLifecycle memory lifecycle = lifecycleView.getTaskLifecycle(taskId);

        _assertLifecycle(
            lifecycle,
            TaskIntentMarket.TaskStatus.Open,
            TaskFundingEscrow.EscrowStatus.None,
            bytes32(0),
            bytes32(0),
            requester,
            bytes32(0),
            0
        );
    }

    function test_ReadsFundedTaskLifecycle() public {
        uint256 taskId = _openAndFundTaskIntent();

        TaskLifecycleView.TaskLifecycle memory lifecycle = lifecycleView.getTaskLifecycle(taskId);

        _assertLifecycle(
            lifecycle,
            TaskIntentMarket.TaskStatus.Open,
            TaskFundingEscrow.EscrowStatus.Funded,
            bytes32(0),
            bytes32(0),
            requester,
            bytes32(0),
            FUNDING_AMOUNT
        );
    }

    function test_ReadsAssignedTaskLifecycle() public {
        uint256 taskId = _openFundAndClaimTaskIntent();

        TaskLifecycleView.TaskLifecycle memory lifecycle = lifecycleView.getTaskLifecycle(taskId);

        _assertLifecycle(
            lifecycle,
            TaskIntentMarket.TaskStatus.Assigned,
            TaskFundingEscrow.EscrowStatus.Funded,
            bytes32(0),
            bytes32(0),
            requester,
            AGENT_ID,
            FUNDING_AMOUNT
        );
    }

    function test_ReadsResultCommittedTaskLifecycle() public {
        uint256 taskId = _openFundClaimAndCommitResult();

        TaskLifecycleView.TaskLifecycle memory lifecycle = lifecycleView.getTaskLifecycle(taskId);

        _assertLifecycle(
            lifecycle,
            TaskIntentMarket.TaskStatus.Assigned,
            TaskFundingEscrow.EscrowStatus.Funded,
            RESULT_HASH,
            bytes32(0),
            requester,
            AGENT_ID,
            FUNDING_AMOUNT
        );
    }

    function test_ReadsAcceptedTaskLifecycle() public {
        uint256 taskId = _openFundClaimCommitAndAcceptResult();

        TaskLifecycleView.TaskLifecycle memory lifecycle = lifecycleView.getTaskLifecycle(taskId);

        _assertLifecycle(
            lifecycle,
            TaskIntentMarket.TaskStatus.Assigned,
            TaskFundingEscrow.EscrowStatus.Funded,
            RESULT_HASH,
            RESULT_HASH,
            requester,
            AGENT_ID,
            FUNDING_AMOUNT
        );
    }

    function test_ReadsReleasedTaskLifecycle() public {
        uint256 taskId = _openFundClaimCommitAndAcceptResult();

        escrow.releaseAcceptedTaskIntent(taskId);

        TaskLifecycleView.TaskLifecycle memory lifecycle = lifecycleView.getTaskLifecycle(taskId);

        _assertLifecycle(
            lifecycle,
            TaskIntentMarket.TaskStatus.Assigned,
            TaskFundingEscrow.EscrowStatus.Released,
            RESULT_HASH,
            RESULT_HASH,
            requester,
            AGENT_ID,
            FUNDING_AMOUNT
        );
    }

    function test_ReadsAuditFieldsFromUnderlyingSources() public {
        uint256 taskId = _openFundClaimCommitAndAcceptResult();

        escrow.releaseAcceptedTaskIntent(taskId);

        TaskLifecycleView.TaskLifecycle memory lifecycle = lifecycleView.getTaskLifecycle(taskId);
        TaskIntentMarket.TaskIntent memory intent = market.getTaskIntent(taskId);
        TaskFundingEscrow.EscrowRecord memory escrowRecord = escrow.getEscrowRecord(taskId);
        TaskResultRegistry.ResultRecord memory result = resultRegistry.getResultRecord(taskId);
        TaskAcceptanceRegistry.AcceptanceRecord memory acceptance = acceptanceRegistry.getAcceptanceRecord(taskId);

        assertEq(lifecycle.escrowPayer, escrowRecord.payer);
        assertEq(lifecycle.resultAgentId, result.agentId);
        assertEq(lifecycle.createdAt, intent.createdAt);
        assertEq(lifecycle.assignedAt, intent.assignedAt);
        assertEq(lifecycle.resultSubmittedAt, result.submittedAt);
        assertEq(lifecycle.acceptedAt, acceptance.acceptedAt);
    }

    function test_ReadsCancelledRefundedTaskLifecycle() public {
        uint256 taskId = _openAndFundTaskIntent();

        vm.prank(requester);
        market.cancelTaskIntent(taskId);

        vm.prank(requester);
        escrow.refundCancelledTaskIntent(taskId);

        TaskLifecycleView.TaskLifecycle memory lifecycle = lifecycleView.getTaskLifecycle(taskId);

        _assertLifecycle(
            lifecycle,
            TaskIntentMarket.TaskStatus.Cancelled,
            TaskFundingEscrow.EscrowStatus.Refunded,
            bytes32(0),
            bytes32(0),
            requester,
            bytes32(0),
            FUNDING_AMOUNT
        );
    }

    function test_ReadDoesNotMutateUnderlyingLifecycle() public {
        uint256 taskId = _openFundClaimAndCommitResult();

        TaskLifecycleView.TaskLifecycle memory beforeRead = lifecycleView.getTaskLifecycle(taskId);
        TaskLifecycleView.TaskLifecycle memory afterRead = lifecycleView.getTaskLifecycle(taskId);

        _assertLifecycle(
            afterRead,
            beforeRead.taskStatus,
            beforeRead.escrowStatus,
            beforeRead.resultHash,
            beforeRead.acceptanceHash,
            beforeRead.requester,
            beforeRead.assignedAgentId,
            beforeRead.escrowAmount
        );
    }

    function _openFundClaimCommitAndAcceptResult() private returns (uint256 taskId) {
        taskId = _openFundClaimAndCommitResult();

        vm.prank(requester);
        acceptanceRegistry.acceptTaskResult(taskId, RESULT_HASH);
    }

    function _openFundClaimAndCommitResult() private returns (uint256 taskId) {
        taskId = _openFundAndClaimTaskIntent();

        vm.prank(owner);
        resultRegistry.commitTaskResult(taskId, RESULT_HASH);
    }

    function _openFundAndClaimTaskIntent() private returns (uint256 taskId) {
        (bytes memory proof, bytes32 actionHash) = _registerAndAttestAgent();

        vm.prank(requester);
        taskId = market.openTaskIntent(actionHash, TASK_DATA_HASH);

        vm.prank(requester);
        escrow.fundTaskIntent{value: FUNDING_AMOUNT}(taskId);

        vm.prank(owner);
        market.claimTaskIntent(taskId, AGENT_ID, proof);
    }

    function _openAndFundTaskIntent() private returns (uint256 taskId) {
        taskId = _openTaskIntent();

        vm.prank(requester);
        escrow.fundTaskIntent{value: FUNDING_AMOUNT}(taskId);
    }

    function _openTaskIntent() private returns (uint256 taskId) {
        vm.prank(requester);
        taskId = market.openTaskIntent(_actionHash(), TASK_DATA_HASH);
    }

    function _registerAndAttestAgent() private returns (bytes memory proof, bytes32 actionHash) {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();

        vm.startPrank(owner);
        registry.registerAgent(AGENT_ID, publicInputs[0]);
        boundary.attestAgent(AGENT_ID);
        vm.stopPrank();

        return (MerkleInclusionFixture.proof(), publicInputs[1]);
    }

    function _actionHash() private pure returns (bytes32) {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();

        return publicInputs[1];
    }

    function _assertLifecycle(
        TaskLifecycleView.TaskLifecycle memory lifecycle,
        TaskIntentMarket.TaskStatus taskStatus,
        TaskFundingEscrow.EscrowStatus escrowStatus,
        bytes32 resultHash,
        bytes32 acceptanceHash,
        address requester_,
        bytes32 assignedAgentId,
        uint256 escrowAmount
    ) private pure {
        assertEq(uint8(lifecycle.taskStatus), uint8(taskStatus));
        assertEq(uint8(lifecycle.escrowStatus), uint8(escrowStatus));
        assertEq(lifecycle.resultHash, resultHash);
        assertEq(lifecycle.acceptanceHash, acceptanceHash);
        assertEq(lifecycle.requester, requester_);
        assertEq(lifecycle.assignedAgentId, assignedAgentId);
        assertEq(lifecycle.escrowAmount, escrowAmount);
    }
}
