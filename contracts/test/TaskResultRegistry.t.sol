// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {EmtunAuthorizationReader} from "../src/EmtunAuthorizationReader.sol";
import {EmtunEASAttestationBoundary} from "../src/EmtunEASAttestationBoundary.sol";
import {EmtunVerifierAdapter} from "../src/EmtunVerifierAdapter.sol";
import {MockEAS} from "../src/MockEAS.sol";
import {PolicyRootChain} from "../src/PolicyRootChain.sol";
import {TaskAuthorizationGate} from "../src/TaskAuthorizationGate.sol";
import {TaskIntentMarket} from "../src/TaskIntentMarket.sol";
import {TaskResultRegistry} from "../src/TaskResultRegistry.sol";
import {HonkVerifier} from "../src/verifiers/EmtunPolicyVerifier.sol";
import {MerkleInclusionFixture} from "./fixtures/MerkleInclusionFixture.sol";

contract TaskResultRegistryTest is Test {
    AgentRegistry internal registry;
    EmtunEASAttestationBoundary internal boundary;
    MockEAS internal eas;
    PolicyRootChain internal rootChain;
    TaskAuthorizationGate internal gate;
    TaskIntentMarket internal market;
    TaskResultRegistry internal resultRegistry;

    bytes32 internal constant AGENT_ID = keccak256("emtun.agent.alpha");
    bytes32 internal constant TASK_DATA_HASH = keccak256("task.intent.payload");
    bytes32 internal constant RESULT_HASH = keccak256("task.result.payload");
    bytes32 internal constant NEXT_RESULT_HASH = keccak256("task.result.next");

    address internal owner = address(0xA11CE);
    address internal nextOwner = address(0xB0B);
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
    }

    function test_AssignedAgentOwnerCommitsTaskResult() public {
        uint256 taskId = _openAndClaimTaskIntent();

        vm.prank(owner);
        resultRegistry.commitTaskResult(taskId, RESULT_HASH);

        TaskResultRegistry.ResultRecord memory record = resultRegistry.getResultRecord(taskId);

        assertEq(record.agentId, AGENT_ID);
        assertEq(record.resultHash, RESULT_HASH);
        assertGt(record.submittedAt, 0);
    }

    function test_RevertsWhenResultHashIsZero() public {
        uint256 taskId = _openAndClaimTaskIntent();

        vm.expectRevert(TaskResultRegistry.InvalidResultHash.selector);
        vm.prank(owner);
        resultRegistry.commitTaskResult(taskId, bytes32(0));
    }

    function test_RevertsWhenTaskIsOpen() public {
        uint256 taskId = _openTaskIntent();

        vm.expectRevert(abi.encodeWithSelector(TaskResultRegistry.TaskNotAssigned.selector, taskId));
        vm.prank(owner);
        resultRegistry.commitTaskResult(taskId, RESULT_HASH);
    }

    function test_RevertsWhenTaskIsCancelled() public {
        uint256 taskId = _openTaskIntent();

        vm.prank(requester);
        market.cancelTaskIntent(taskId);

        vm.expectRevert(abi.encodeWithSelector(TaskResultRegistry.TaskNotAssigned.selector, taskId));
        vm.prank(owner);
        resultRegistry.commitTaskResult(taskId, RESULT_HASH);
    }

    function test_OnlyAssignedAgentOwnerCanCommitTaskResult() public {
        uint256 taskId = _openAndClaimTaskIntent();

        vm.expectRevert(
            abi.encodeWithSelector(TaskResultRegistry.NotAssignedAgentOwner.selector, taskId, AGENT_ID, stranger)
        );
        vm.prank(stranger);
        resultRegistry.commitTaskResult(taskId, RESULT_HASH);
    }

    function test_CurrentOwnerCanCommitAfterAgentOwnerTransfer() public {
        uint256 taskId = _openAndClaimTaskIntent();

        vm.prank(owner);
        registry.transferAgentOwner(AGENT_ID, nextOwner);

        vm.expectRevert(
            abi.encodeWithSelector(TaskResultRegistry.NotAssignedAgentOwner.selector, taskId, AGENT_ID, owner)
        );
        vm.prank(owner);
        resultRegistry.commitTaskResult(taskId, RESULT_HASH);

        vm.prank(nextOwner);
        resultRegistry.commitTaskResult(taskId, RESULT_HASH);

        TaskResultRegistry.ResultRecord memory record = resultRegistry.getResultRecord(taskId);

        assertEq(record.agentId, AGENT_ID);
        assertEq(record.resultHash, RESULT_HASH);
    }

    function test_RevertsWhenResultAlreadySubmitted() public {
        uint256 taskId = _openAndClaimTaskIntent();

        vm.prank(owner);
        resultRegistry.commitTaskResult(taskId, RESULT_HASH);

        vm.expectRevert(abi.encodeWithSelector(TaskResultRegistry.ResultAlreadySubmitted.selector, taskId, RESULT_HASH));
        vm.prank(owner);
        resultRegistry.commitTaskResult(taskId, NEXT_RESULT_HASH);
    }

    function test_RevertsWhenAgentRegistryIsNotContract() public {
        vm.expectRevert(TaskResultRegistry.InvalidAgentRegistry.selector);
        new TaskResultRegistry(address(0), address(market));
    }

    function test_RevertsWhenTaskIntentMarketIsNotContract() public {
        vm.expectRevert(TaskResultRegistry.InvalidTaskIntentMarket.selector);
        new TaskResultRegistry(address(registry), address(0));
    }

    function _openAndClaimTaskIntent() private returns (uint256 taskId) {
        (bytes memory proof, bytes32 actionHash) = _registerAndAttestAgent();

        vm.prank(requester);
        taskId = market.openTaskIntent(actionHash, TASK_DATA_HASH);

        vm.prank(owner);
        market.claimTaskIntent(taskId, AGENT_ID, proof);
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
}
