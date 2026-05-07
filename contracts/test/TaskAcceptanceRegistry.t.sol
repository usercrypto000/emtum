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
import {TaskIntentMarket} from "../src/TaskIntentMarket.sol";
import {TaskResultRegistry} from "../src/TaskResultRegistry.sol";
import {HonkVerifier} from "../src/verifiers/EmtunPolicyVerifier.sol";
import {MerkleInclusionFixture} from "./fixtures/MerkleInclusionFixture.sol";

contract TaskAcceptanceRegistryTest is Test {
    AgentRegistry internal registry;
    EmtunEASAttestationBoundary internal boundary;
    MockEAS internal eas;
    PolicyRootChain internal rootChain;
    TaskAuthorizationGate internal gate;
    TaskIntentMarket internal market;
    TaskResultRegistry internal resultRegistry;
    TaskAcceptanceRegistry internal acceptanceRegistry;

    bytes32 internal constant AGENT_ID = keccak256("emtun.agent.alpha");
    bytes32 internal constant TASK_DATA_HASH = keccak256("task.intent.payload");
    bytes32 internal constant RESULT_HASH = keccak256("task.result.payload");
    bytes32 internal constant WRONG_RESULT_HASH = keccak256("task.result.wrong");

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
    }

    function test_RequesterAcceptsCommittedResult() public {
        uint256 taskId = _openClaimAndCommitResult();

        vm.prank(requester);
        acceptanceRegistry.acceptTaskResult(taskId, RESULT_HASH);

        TaskAcceptanceRegistry.AcceptanceRecord memory record = acceptanceRegistry.getAcceptanceRecord(taskId);

        assertEq(record.acceptedBy, requester);
        assertEq(record.resultHash, RESULT_HASH);
        assertGt(record.acceptedAt, 0);
    }

    function test_RevertsWhenResultHashIsZero() public {
        uint256 taskId = _openClaimAndCommitResult();

        vm.expectRevert(TaskAcceptanceRegistry.InvalidResultHash.selector);
        vm.prank(requester);
        acceptanceRegistry.acceptTaskResult(taskId, bytes32(0));
    }

    function test_RevertsWhenTaskIsOpen() public {
        vm.prank(requester);
        uint256 taskId = market.openTaskIntent(_actionHash(), TASK_DATA_HASH);

        vm.expectRevert(abi.encodeWithSelector(TaskAcceptanceRegistry.TaskNotAssigned.selector, taskId));
        vm.prank(requester);
        acceptanceRegistry.acceptTaskResult(taskId, RESULT_HASH);
    }

    function test_RevertsWhenTaskIsCancelled() public {
        vm.prank(requester);
        uint256 taskId = market.openTaskIntent(_actionHash(), TASK_DATA_HASH);

        vm.prank(requester);
        market.cancelTaskIntent(taskId);

        vm.expectRevert(abi.encodeWithSelector(TaskAcceptanceRegistry.TaskNotAssigned.selector, taskId));
        vm.prank(requester);
        acceptanceRegistry.acceptTaskResult(taskId, RESULT_HASH);
    }

    function test_RevertsWhenResultNotSubmitted() public {
        uint256 taskId = _openAndClaimTaskIntent();

        vm.expectRevert(abi.encodeWithSelector(TaskAcceptanceRegistry.ResultNotSubmitted.selector, taskId));
        vm.prank(requester);
        acceptanceRegistry.acceptTaskResult(taskId, RESULT_HASH);
    }

    function test_OnlyRequesterCanAcceptResult() public {
        uint256 taskId = _openClaimAndCommitResult();

        vm.expectRevert(abi.encodeWithSelector(TaskAcceptanceRegistry.NotTaskRequester.selector, taskId, stranger));
        vm.prank(stranger);
        acceptanceRegistry.acceptTaskResult(taskId, RESULT_HASH);
    }

    function test_RevertsWhenResultHashDoesNotMatchCommittedResult() public {
        uint256 taskId = _openClaimAndCommitResult();

        vm.expectRevert(
            abi.encodeWithSelector(
                TaskAcceptanceRegistry.ResultHashMismatch.selector, taskId, RESULT_HASH, WRONG_RESULT_HASH
            )
        );
        vm.prank(requester);
        acceptanceRegistry.acceptTaskResult(taskId, WRONG_RESULT_HASH);
    }

    function test_RevertsWhenResultAlreadyAccepted() public {
        uint256 taskId = _openClaimAndCommitResult();

        vm.prank(requester);
        acceptanceRegistry.acceptTaskResult(taskId, RESULT_HASH);

        vm.expectRevert(
            abi.encodeWithSelector(TaskAcceptanceRegistry.ResultAlreadyAccepted.selector, taskId, RESULT_HASH)
        );
        vm.prank(requester);
        acceptanceRegistry.acceptTaskResult(taskId, RESULT_HASH);
    }

    function test_RevertsWhenTaskIntentMarketIsNotContract() public {
        vm.expectRevert(TaskAcceptanceRegistry.InvalidTaskIntentMarket.selector);
        new TaskAcceptanceRegistry(address(0), address(resultRegistry));
    }

    function test_RevertsWhenTaskResultRegistryIsNotContract() public {
        vm.expectRevert(TaskAcceptanceRegistry.InvalidTaskResultRegistry.selector);
        new TaskAcceptanceRegistry(address(market), address(0));
    }

    function _openClaimAndCommitResult() private returns (uint256 taskId) {
        taskId = _openAndClaimTaskIntent();

        vm.prank(owner);
        resultRegistry.commitTaskResult(taskId, RESULT_HASH);
    }

    function _openAndClaimTaskIntent() private returns (uint256 taskId) {
        (bytes memory proof, bytes32 actionHash) = _registerAndAttestAgent();

        vm.prank(requester);
        taskId = market.openTaskIntent(actionHash, TASK_DATA_HASH);

        vm.prank(owner);
        market.claimTaskIntent(taskId, AGENT_ID, proof);
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
