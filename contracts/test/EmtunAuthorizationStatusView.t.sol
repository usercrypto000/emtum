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
import {HonkVerifier} from "../src/verifiers/EmtunPolicyVerifier.sol";
import {MerkleInclusionFixture} from "./fixtures/MerkleInclusionFixture.sol";

contract EmtunAuthorizationStatusViewTest is Test {
    AgentRegistry internal registry;
    EmtunEASAttestationBoundary internal boundary;
    EmtunAuthorizationReader internal reader;
    EmtunAuthorizationStatusView internal statusView;
    MockEAS internal eas;
    PolicyRootChain internal rootChain;

    bytes32 internal constant AGENT_ID = keccak256("emtun.agent.alpha");
    bytes32 internal constant NEXT_ROOT = keccak256("policy.root.next");

    address internal owner = address(0xA11CE);

    function setUp() public {
        rootChain = new PolicyRootChain();
        HonkVerifier honkVerifier = new HonkVerifier();
        EmtunVerifierAdapter adapter = new EmtunVerifierAdapter(address(honkVerifier));
        reader = new EmtunAuthorizationReader(address(rootChain), address(adapter));

        registry = new AgentRegistry(address(rootChain));
        eas = new MockEAS();
        boundary = new EmtunEASAttestationBoundary(address(registry), address(eas));
        statusView = new EmtunAuthorizationStatusView(address(registry), address(boundary), address(reader));
    }

    function test_ReadsUnregisteredAgentAsInactive() public view {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();

        EmtunAuthorizationStatusView.AgentAuthorizationStatus memory status =
            statusView.getAgentAuthorizationStatus(AGENT_ID, MerkleInclusionFixture.proof(), publicInputs[1]);

        assertFalse(status.registered);
        assertFalse(status.activeAttestation);
        assertFalse(status.authorized);
        assertEq(status.owner, address(0));
        assertEq(status.policyRoot, bytes32(0));
        assertEq(status.registeredAt, 0);
    }

    function test_ReadsAuthorizedRegisteredAttestedAgent() public {
        (bytes memory proof, bytes32 policyRoot, bytes32 actionHash) = _registerAndAttestAgent();

        EmtunAuthorizationStatusView.AgentAuthorizationStatus memory status =
            statusView.getAgentAuthorizationStatus(AGENT_ID, proof, actionHash);

        assertTrue(status.registered);
        assertTrue(status.activeAttestation);
        assertTrue(status.authorized);
        assertEq(status.owner, owner);
        assertEq(status.policyRoot, policyRoot);
        assertGt(status.registeredAt, 0);
    }

    function test_ReportsInactiveAuthorizationWithoutAttestation() public {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();

        vm.prank(owner);
        registry.registerAgent(AGENT_ID, publicInputs[0]);

        EmtunAuthorizationStatusView.AgentAuthorizationStatus memory status =
            statusView.getAgentAuthorizationStatus(AGENT_ID, MerkleInclusionFixture.proof(), publicInputs[1]);

        assertTrue(status.registered);
        assertFalse(status.activeAttestation);
        assertFalse(status.authorized);
        assertEq(status.owner, owner);
        assertEq(status.policyRoot, publicInputs[0]);
    }

    function test_ReportsInactiveAuthorizationForWrongActionHash() public {
        (bytes memory proof,,) = _registerAndAttestAgent();

        EmtunAuthorizationStatusView.AgentAuthorizationStatus memory status =
            statusView.getAgentAuthorizationStatus(AGENT_ID, proof, keccak256("wrong.action"));

        assertTrue(status.registered);
        assertTrue(status.activeAttestation);
        assertFalse(status.authorized);
    }

    function test_ReportsCurrentRootAfterPolicyRotation() public {
        (bytes memory proof,, bytes32 actionHash) = _registerAndAttestAgent();

        vm.prank(owner);
        rootChain.updateRoot(AGENT_ID, NEXT_ROOT);

        EmtunAuthorizationStatusView.AgentAuthorizationStatus memory status =
            statusView.getAgentAuthorizationStatus(AGENT_ID, proof, actionHash);

        assertTrue(status.registered);
        assertTrue(status.activeAttestation);
        assertFalse(status.authorized);
        assertEq(status.policyRoot, NEXT_ROOT);
    }

    function test_RevertsWhenAgentRegistryIsNotContract() public {
        vm.expectRevert(EmtunAuthorizationStatusView.InvalidAgentRegistry.selector);
        new EmtunAuthorizationStatusView(address(0), address(boundary), address(reader));
    }

    function test_RevertsWhenAttestationBoundaryIsNotContract() public {
        vm.expectRevert(EmtunAuthorizationStatusView.InvalidAttestationBoundary.selector);
        new EmtunAuthorizationStatusView(address(registry), address(0), address(reader));
    }

    function test_RevertsWhenAuthorizationReaderIsNotContract() public {
        vm.expectRevert(EmtunAuthorizationStatusView.InvalidAuthorizationReader.selector);
        new EmtunAuthorizationStatusView(address(registry), address(boundary), address(0));
    }

    function _registerAndAttestAgent() private returns (bytes memory proof, bytes32 policyRoot, bytes32 actionHash) {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();
        proof = MerkleInclusionFixture.proof();
        policyRoot = publicInputs[0];
        actionHash = publicInputs[1];

        vm.startPrank(owner);
        registry.registerAgent(AGENT_ID, policyRoot);
        boundary.attestAgent(AGENT_ID);
        vm.stopPrank();
    }
}
