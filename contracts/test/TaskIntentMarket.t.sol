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
import {HonkVerifier} from "../src/verifiers/EmtunPolicyVerifier.sol";
import {MerkleInclusionFixture} from "./fixtures/MerkleInclusionFixture.sol";

contract TaskIntentMarketTest is Test {
    AgentRegistry internal registry;
    EmtunEASAttestationBoundary internal boundary;
    MockEAS internal eas;
    PolicyRootChain internal rootChain;
    TaskAuthorizationGate internal gate;
    TaskIntentMarket internal market;

    bytes32 internal constant AGENT_ID = keccak256("emtun.agent.alpha");
    bytes32 internal constant UNREGISTERED_AGENT_ID = keccak256("emtun.agent.unregistered");
    bytes32 internal constant TASK_DATA_HASH = keccak256("task.intent.payload");
    bytes32 internal constant NEXT_ROOT = keccak256("policy.root.next");

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
    }

    function test_RequesterOpensTaskIntent() public {
        bytes32 actionHash = _actionHash();

        vm.prank(requester);
        uint256 taskId = market.openTaskIntent(actionHash, TASK_DATA_HASH);

        TaskIntentMarket.TaskIntent memory intent = market.getTaskIntent(taskId);

        assertEq(taskId, 1);
        assertEq(market.nextTaskId(), 2);
        assertEq(intent.requester, requester);
        assertEq(intent.actionHash, actionHash);
        assertEq(intent.taskDataHash, TASK_DATA_HASH);
        assertEq(uint8(intent.status), uint8(TaskIntentMarket.TaskStatus.Open));
    }

    function test_AuthorizedAgentClaimsOpenTaskIntent() public {
        (bytes memory proof, bytes32 actionHash) = _registerAndAttestAgent();

        vm.prank(requester);
        uint256 taskId = market.openTaskIntent(actionHash, TASK_DATA_HASH);

        vm.prank(owner);
        market.claimTaskIntent(taskId, AGENT_ID, proof);

        TaskIntentMarket.TaskIntent memory intent = market.getTaskIntent(taskId);

        assertEq(intent.assignedAgentId, AGENT_ID);
        assertGt(intent.assignedAt, 0);
        assertEq(uint8(intent.status), uint8(TaskIntentMarket.TaskStatus.Assigned));
    }

    function test_RejectsUnauthorizedTaskClaim() public {
        bytes32 actionHash = _actionHash();

        vm.prank(requester);
        uint256 taskId = market.openTaskIntent(actionHash, TASK_DATA_HASH);

        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.AgentNotRegistered.selector, UNREGISTERED_AGENT_ID));
        market.claimTaskIntent(taskId, UNREGISTERED_AGENT_ID, MerkleInclusionFixture.proof());
    }

    function test_OnlyCurrentAgentOwnerCanClaimTaskIntent() public {
        (bytes memory proof, bytes32 actionHash) = _registerAndAttestAgent();

        vm.prank(requester);
        uint256 taskId = market.openTaskIntent(actionHash, TASK_DATA_HASH);

        vm.expectRevert(abi.encodeWithSelector(TaskIntentMarket.NotAgentOwner.selector, AGENT_ID, stranger));
        vm.prank(stranger);
        market.claimTaskIntent(taskId, AGENT_ID, proof);
    }

    function test_RejectsStaleRootTaskClaim() public {
        (bytes memory proof, bytes32 actionHash) = _registerAndAttestAgent();

        vm.prank(requester);
        uint256 taskId = market.openTaskIntent(actionHash, TASK_DATA_HASH);

        vm.prank(owner);
        rootChain.updateRoot(AGENT_ID, NEXT_ROOT);

        vm.expectRevert(
            abi.encodeWithSelector(TaskIntentMarket.UnauthorizedTaskClaim.selector, taskId, AGENT_ID, actionHash)
        );
        vm.prank(owner);
        market.claimTaskIntent(taskId, AGENT_ID, proof);
    }

    function test_RejectsSecondClaimAfterAssignment() public {
        (bytes memory proof, bytes32 actionHash) = _registerAndAttestAgent();

        vm.prank(requester);
        uint256 taskId = market.openTaskIntent(actionHash, TASK_DATA_HASH);

        vm.prank(owner);
        market.claimTaskIntent(taskId, AGENT_ID, proof);

        vm.expectRevert(abi.encodeWithSelector(TaskIntentMarket.TaskNotOpen.selector, taskId));
        vm.prank(owner);
        market.claimTaskIntent(taskId, AGENT_ID, proof);
    }

    function test_RequesterCanCancelOpenTaskIntent() public {
        bytes32 actionHash = _actionHash();

        vm.prank(requester);
        uint256 taskId = market.openTaskIntent(actionHash, TASK_DATA_HASH);

        vm.prank(requester);
        market.cancelTaskIntent(taskId);

        TaskIntentMarket.TaskIntent memory intent = market.getTaskIntent(taskId);

        assertEq(uint8(intent.status), uint8(TaskIntentMarket.TaskStatus.Cancelled));
    }

    function test_OnlyRequesterCanCancelTaskIntent() public {
        bytes32 actionHash = _actionHash();

        vm.prank(requester);
        uint256 taskId = market.openTaskIntent(actionHash, TASK_DATA_HASH);

        vm.expectRevert(abi.encodeWithSelector(TaskIntentMarket.NotTaskRequester.selector, taskId, stranger));
        vm.prank(stranger);
        market.cancelTaskIntent(taskId);
    }

    function test_RevertsWhenOpeningTaskWithZeroActionHash() public {
        vm.expectRevert(TaskIntentMarket.InvalidActionHash.selector);
        market.openTaskIntent(bytes32(0), TASK_DATA_HASH);
    }

    function test_RevertsWhenOpeningTaskWithZeroTaskDataHash() public {
        vm.expectRevert(TaskIntentMarket.InvalidTaskDataHash.selector);
        market.openTaskIntent(_actionHash(), bytes32(0));
    }

    function test_RevertsWhenGateIsNotContract() public {
        vm.expectRevert(TaskIntentMarket.InvalidAuthorizationGate.selector);
        new TaskIntentMarket(address(registry), address(0));
    }

    function test_RevertsWhenAgentRegistryIsNotContract() public {
        vm.expectRevert(TaskIntentMarket.InvalidAgentRegistry.selector);
        new TaskIntentMarket(address(0), address(gate));
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
