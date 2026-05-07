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
import {TaskResultRegistry} from "../src/TaskResultRegistry.sol";
import {HonkVerifier} from "../src/verifiers/EmtunPolicyVerifier.sol";
import {MerkleInclusionFixture} from "./fixtures/MerkleInclusionFixture.sol";

contract RejectingEscrowPayer {
    TaskIntentMarket internal immutable market;
    TaskFundingEscrow internal immutable escrow;

    constructor(TaskIntentMarket market_, TaskFundingEscrow escrow_) {
        market = market_;
        escrow = escrow_;
    }

    receive() external payable {
        revert("reject refund");
    }

    function openAndFund(bytes32 actionHash, bytes32 taskDataHash) external payable returns (uint256 taskId) {
        taskId = market.openTaskIntent(actionHash, taskDataHash);
        escrow.fundTaskIntent{value: msg.value}(taskId);
    }

    function cancel(uint256 taskId) external {
        market.cancelTaskIntent(taskId);
    }

    function requestRefund(uint256 taskId) external {
        escrow.refundCancelledTaskIntent(taskId);
    }
}

contract RejectingAgentOwner {
    AgentRegistry internal immutable registry;
    EmtunEASAttestationBoundary internal immutable boundary;
    TaskIntentMarket internal immutable market;
    TaskResultRegistry internal immutable resultRegistry;

    constructor(
        AgentRegistry registry_,
        EmtunEASAttestationBoundary boundary_,
        TaskIntentMarket market_,
        TaskResultRegistry resultRegistry_
    ) {
        registry = registry_;
        boundary = boundary_;
        market = market_;
        resultRegistry = resultRegistry_;
    }

    receive() external payable {
        revert("reject payout");
    }

    function registerAndAttest(bytes32 agentId, bytes32 policyRoot) external {
        registry.registerAgent(agentId, policyRoot);
        boundary.attestAgent(agentId);
    }

    function claimTaskIntent(uint256 taskId, bytes32 agentId, bytes calldata proof) external {
        market.claimTaskIntent(taskId, agentId, proof);
    }

    function commitTaskResult(uint256 taskId, bytes32 resultHash) external {
        resultRegistry.commitTaskResult(taskId, resultHash);
    }
}

contract TaskFundingEscrowTest is Test {
    AgentRegistry internal registry;
    EmtunEASAttestationBoundary internal boundary;
    MockEAS internal eas;
    PolicyRootChain internal rootChain;
    TaskAuthorizationGate internal gate;
    TaskIntentMarket internal market;
    TaskFundingEscrow internal escrow;
    TaskResultRegistry internal resultRegistry;
    TaskAcceptanceRegistry internal acceptanceRegistry;

    bytes32 internal constant AGENT_ID = keccak256("emtun.agent.alpha");
    bytes32 internal constant TASK_DATA_HASH = keccak256("task.intent.payload");
    bytes32 internal constant RESULT_HASH = keccak256("task.result.payload");
    uint256 internal constant FUNDING_AMOUNT = 1 ether;

    address internal owner = address(0xA11CE);
    address internal requester = address(0xCAFE);
    address internal stranger = address(0xBAD);

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

        vm.deal(requester, 10 ether);
        vm.deal(stranger, 10 ether);
    }

    function test_RequesterFundsOpenTaskIntent() public {
        uint256 taskId = _openTaskIntent();

        vm.prank(requester);
        escrow.fundTaskIntent{value: FUNDING_AMOUNT}(taskId);

        TaskFundingEscrow.EscrowRecord memory record = escrow.getEscrowRecord(taskId);

        assertEq(record.payer, requester);
        assertEq(record.amount, FUNDING_AMOUNT);
        assertEq(uint8(record.status), uint8(TaskFundingEscrow.EscrowStatus.Funded));
        assertEq(address(escrow).balance, FUNDING_AMOUNT);
    }

    function test_RevertsWhenFundingWithZeroValue() public {
        uint256 taskId = _openTaskIntent();

        vm.expectRevert(TaskFundingEscrow.InvalidFundingAmount.selector);
        vm.prank(requester);
        escrow.fundTaskIntent(taskId);
    }

    function test_OnlyRequesterCanFundTaskIntent() public {
        uint256 taskId = _openTaskIntent();

        vm.expectRevert(abi.encodeWithSelector(TaskFundingEscrow.NotTaskRequester.selector, taskId, stranger));
        vm.prank(stranger);
        escrow.fundTaskIntent{value: FUNDING_AMOUNT}(taskId);
    }

    function test_RevertsWhenFundingCancelledTaskIntent() public {
        uint256 taskId = _openTaskIntent();

        vm.prank(requester);
        market.cancelTaskIntent(taskId);

        vm.expectRevert(abi.encodeWithSelector(TaskFundingEscrow.TaskNotOpen.selector, taskId));
        vm.prank(requester);
        escrow.fundTaskIntent{value: FUNDING_AMOUNT}(taskId);
    }

    function test_RevertsWhenFundingAssignedTaskIntent() public {
        (bytes memory proof, bytes32 actionHash) = _registerAndAttestAgent();

        vm.prank(requester);
        uint256 taskId = market.openTaskIntent(actionHash, TASK_DATA_HASH);

        vm.prank(owner);
        market.claimTaskIntent(taskId, AGENT_ID, proof);

        vm.expectRevert(abi.encodeWithSelector(TaskFundingEscrow.TaskNotOpen.selector, taskId));
        vm.prank(requester);
        escrow.fundTaskIntent{value: FUNDING_AMOUNT}(taskId);
    }

    function test_RevertsWhenFundingTwice() public {
        uint256 taskId = _openTaskIntent();

        vm.prank(requester);
        escrow.fundTaskIntent{value: FUNDING_AMOUNT}(taskId);

        vm.expectRevert(abi.encodeWithSelector(TaskFundingEscrow.EscrowAlreadyFunded.selector, taskId));
        vm.prank(requester);
        escrow.fundTaskIntent{value: FUNDING_AMOUNT}(taskId);
    }

    function test_RequesterRefundsCancelledTaskIntent() public {
        uint256 taskId = _openAndFundTaskIntent();
        uint256 requesterBalanceBefore = requester.balance;

        vm.prank(requester);
        market.cancelTaskIntent(taskId);

        vm.prank(requester);
        escrow.refundCancelledTaskIntent(taskId);

        TaskFundingEscrow.EscrowRecord memory record = escrow.getEscrowRecord(taskId);

        assertEq(record.payer, requester);
        assertEq(record.amount, FUNDING_AMOUNT);
        assertEq(uint8(record.status), uint8(TaskFundingEscrow.EscrowStatus.Refunded));
        assertEq(requester.balance, requesterBalanceBefore + FUNDING_AMOUNT);
        assertEq(address(escrow).balance, 0);
    }

    function test_RevertsWhenRefundingBeforeCancellation() public {
        uint256 taskId = _openAndFundTaskIntent();

        vm.expectRevert(abi.encodeWithSelector(TaskFundingEscrow.TaskNotCancelled.selector, taskId));
        vm.prank(requester);
        escrow.refundCancelledTaskIntent(taskId);
    }

    function test_OnlyEscrowPayerCanRefundCancelledTaskIntent() public {
        uint256 taskId = _openAndFundTaskIntent();

        vm.prank(requester);
        market.cancelTaskIntent(taskId);

        vm.expectRevert(abi.encodeWithSelector(TaskFundingEscrow.NotEscrowPayer.selector, taskId, stranger));
        vm.prank(stranger);
        escrow.refundCancelledTaskIntent(taskId);
    }

    function test_RevertsWhenRefundingUnfundedTaskIntent() public {
        uint256 taskId = _openTaskIntent();

        vm.prank(requester);
        market.cancelTaskIntent(taskId);

        vm.expectRevert(abi.encodeWithSelector(TaskFundingEscrow.EscrowNotFunded.selector, taskId));
        vm.prank(requester);
        escrow.refundCancelledTaskIntent(taskId);
    }

    function test_RevertsWhenRefundRecipientRejectsEth() public {
        RejectingEscrowPayer payer = new RejectingEscrowPayer(market, escrow);
        vm.deal(address(payer), FUNDING_AMOUNT);

        uint256 taskId = payer.openAndFund{value: FUNDING_AMOUNT}(_actionHash(), TASK_DATA_HASH);
        payer.cancel(taskId);

        vm.expectRevert(
            abi.encodeWithSelector(TaskFundingEscrow.RefundFailed.selector, taskId, address(payer), FUNDING_AMOUNT)
        );
        payer.requestRefund(taskId);
    }

    function test_ReleasesAcceptedTaskIntentToCurrentAgentOwner() public {
        uint256 taskId = _openFundClaimCommitAndAccept();
        uint256 ownerBalanceBefore = owner.balance;

        vm.prank(stranger);
        escrow.releaseAcceptedTaskIntent(taskId);

        TaskFundingEscrow.EscrowRecord memory record = escrow.getEscrowRecord(taskId);

        assertEq(record.payer, requester);
        assertEq(record.amount, FUNDING_AMOUNT);
        assertEq(uint8(record.status), uint8(TaskFundingEscrow.EscrowStatus.Released));
        assertEq(owner.balance, ownerBalanceBefore + FUNDING_AMOUNT);
        assertEq(address(escrow).balance, 0);
    }

    function test_ReleasesAcceptedTaskIntentToTransferredAgentOwner() public {
        uint256 taskId = _openFundClaimCommitAndAccept();
        uint256 strangerBalanceBefore = stranger.balance;

        vm.prank(owner);
        registry.transferAgentOwner(AGENT_ID, stranger);

        escrow.releaseAcceptedTaskIntent(taskId);

        TaskFundingEscrow.EscrowRecord memory record = escrow.getEscrowRecord(taskId);

        assertEq(uint8(record.status), uint8(TaskFundingEscrow.EscrowStatus.Released));
        assertEq(stranger.balance, strangerBalanceBefore + FUNDING_AMOUNT);
        assertEq(address(escrow).balance, 0);
    }

    function test_RevertsWhenReleasingBeforeResultAcceptance() public {
        (bytes memory proof, bytes32 actionHash) = _registerAndAttestAgent();

        vm.prank(requester);
        uint256 taskId = market.openTaskIntent(actionHash, TASK_DATA_HASH);
        vm.prank(requester);
        escrow.fundTaskIntent{value: FUNDING_AMOUNT}(taskId);
        vm.prank(owner);
        market.claimTaskIntent(taskId, AGENT_ID, proof);

        vm.expectRevert(abi.encodeWithSelector(TaskFundingEscrow.TaskResultNotAccepted.selector, taskId));
        escrow.releaseAcceptedTaskIntent(taskId);
    }

    function test_RevertsWhenReleasingUnfundedTaskIntent() public {
        uint256 taskId = _openTaskIntent();

        vm.expectRevert(abi.encodeWithSelector(TaskFundingEscrow.EscrowNotFunded.selector, taskId));
        escrow.releaseAcceptedTaskIntent(taskId);
    }

    function test_RevertsWhenReleasingTwice() public {
        uint256 taskId = _openFundClaimCommitAndAccept();

        escrow.releaseAcceptedTaskIntent(taskId);

        vm.expectRevert(abi.encodeWithSelector(TaskFundingEscrow.EscrowNotFunded.selector, taskId));
        escrow.releaseAcceptedTaskIntent(taskId);
    }

    function test_RevertsWhenPayoutRecipientRejectsEth() public {
        RejectingAgentOwner rejectingOwner = new RejectingAgentOwner(registry, boundary, market, resultRegistry);
        bytes memory proof = MerkleInclusionFixture.proof();
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();
        bytes32 policyRoot = publicInputs[0];
        bytes32 actionHash = publicInputs[1];

        rejectingOwner.registerAndAttest(AGENT_ID, policyRoot);

        vm.prank(requester);
        uint256 taskId = market.openTaskIntent(actionHash, TASK_DATA_HASH);
        vm.prank(requester);
        escrow.fundTaskIntent{value: FUNDING_AMOUNT}(taskId);
        rejectingOwner.claimTaskIntent(taskId, AGENT_ID, proof);
        rejectingOwner.commitTaskResult(taskId, RESULT_HASH);
        vm.prank(requester);
        acceptanceRegistry.acceptTaskResult(taskId, RESULT_HASH);

        vm.expectRevert(
            abi.encodeWithSelector(
                TaskFundingEscrow.PayoutFailed.selector, taskId, address(rejectingOwner), FUNDING_AMOUNT
            )
        );
        escrow.releaseAcceptedTaskIntent(taskId);

        TaskFundingEscrow.EscrowRecord memory record = escrow.getEscrowRecord(taskId);

        assertEq(uint8(record.status), uint8(TaskFundingEscrow.EscrowStatus.Funded));
        assertEq(address(escrow).balance, FUNDING_AMOUNT);
    }

    function test_RevertsWhenTaskIntentMarketIsNotContract() public {
        vm.expectRevert(TaskFundingEscrow.InvalidTaskIntentMarket.selector);
        new TaskFundingEscrow(address(registry), address(0), address(acceptanceRegistry));
    }

    function test_RevertsWhenAgentRegistryIsNotContract() public {
        vm.expectRevert(TaskFundingEscrow.InvalidAgentRegistry.selector);
        new TaskFundingEscrow(address(0), address(market), address(acceptanceRegistry));
    }

    function test_RevertsWhenTaskAcceptanceRegistryIsNotContract() public {
        vm.expectRevert(TaskFundingEscrow.InvalidTaskAcceptanceRegistry.selector);
        new TaskFundingEscrow(address(registry), address(market), address(0));
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

    function _openFundClaimCommitAndAccept() private returns (uint256 taskId) {
        (bytes memory proof, bytes32 actionHash) = _registerAndAttestAgent();

        vm.prank(requester);
        taskId = market.openTaskIntent(actionHash, TASK_DATA_HASH);
        vm.prank(requester);
        escrow.fundTaskIntent{value: FUNDING_AMOUNT}(taskId);
        vm.prank(owner);
        market.claimTaskIntent(taskId, AGENT_ID, proof);
        vm.prank(owner);
        resultRegistry.commitTaskResult(taskId, RESULT_HASH);
        vm.prank(requester);
        acceptanceRegistry.acceptTaskResult(taskId, RESULT_HASH);
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
}
