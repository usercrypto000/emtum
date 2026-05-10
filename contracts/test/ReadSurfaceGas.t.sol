// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {EmtunAuthorizationReader} from "../src/EmtunAuthorizationReader.sol";
import {EmtunAuthorizationStatusView} from "../src/EmtunAuthorizationStatusView.sol";
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

contract ReadSurfaceGasTest is Test {
    AgentRegistry internal registry;
    EmtunEASAttestationBoundary internal boundary;
    EmtunAuthorizationStatusView internal statusView;
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
        MockEAS eas = new MockEAS();
        boundary = new EmtunEASAttestationBoundary(address(registry), address(eas));
        statusView = new EmtunAuthorizationStatusView(address(registry), address(boundary), address(reader));
        gate = new TaskAuthorizationGate(address(registry), address(boundary), address(reader));
        market = new TaskIntentMarket(address(registry), address(gate));
        resultRegistry = new TaskResultRegistry(address(registry), address(market));
        acceptanceRegistry = new TaskAcceptanceRegistry(address(market), address(resultRegistry));
        escrow = new TaskFundingEscrow(address(registry), address(market), address(acceptanceRegistry));
        lifecycleView = new TaskLifecycleView(
            address(market), address(escrow), address(resultRegistry), address(acceptanceRegistry)
        );
    }

    function test_Gas_ReadAuthorizedStatusView() public {
        bytes memory proof = MerkleInclusionFixture.proof();
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();

        vm.startPrank(owner);
        registry.registerAgent(AGENT_ID, publicInputs[0]);
        boundary.attestAgent(AGENT_ID);
        vm.stopPrank();

        uint256 gasBefore = gasleft();
        EmtunAuthorizationStatusView.AgentAuthorizationStatus memory status =
            statusView.getAgentAuthorizationStatus(AGENT_ID, proof, publicInputs[1]);
        uint256 gasUsed = gasBefore - gasleft();

        assertTrue(status.authorized);
        emit log_named_uint("authorization_status_view_gas", gasUsed);
    }

    function test_Gas_ReadReleasedLifecycleView() public {
        bytes memory proof = MerkleInclusionFixture.proof();
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();

        vm.startPrank(owner);
        registry.registerAgent(AGENT_ID, publicInputs[0]);
        boundary.attestAgent(AGENT_ID);
        vm.stopPrank();

        vm.deal(requester, FUNDING_AMOUNT);
        vm.prank(requester);
        uint256 taskId = market.openTaskIntent(publicInputs[1], TASK_DATA_HASH);
        vm.prank(requester);
        escrow.fundTaskIntent{value: FUNDING_AMOUNT}(taskId);
        vm.prank(owner);
        market.claimTaskIntent(taskId, AGENT_ID, proof);
        vm.prank(owner);
        resultRegistry.commitTaskResult(taskId, RESULT_HASH);
        vm.prank(requester);
        acceptanceRegistry.acceptTaskResult(taskId, RESULT_HASH);
        escrow.releaseAcceptedTaskIntent(taskId);

        uint256 gasBefore = gasleft();
        TaskLifecycleView.TaskLifecycle memory lifecycle = lifecycleView.getTaskLifecycle(taskId);
        uint256 gasUsed = gasBefore - gasleft();

        assertTrue(lifecycle.isReleased);
        emit log_named_uint("task_lifecycle_view_gas", gasUsed);
    }
}
