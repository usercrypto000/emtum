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
import {HonkVerifier} from "../src/verifiers/EmtunPolicyVerifier.sol";
import {MerkleInclusionFixture} from "./fixtures/MerkleInclusionFixture.sol";

contract TaskAuthorizationGateTest is Test {
    AgentRegistry internal registry;
    EmtunAuthorizationReader internal reader;
    EmtunEASAttestationBoundary internal boundary;
    MockEAS internal eas;
    PolicyRootChain internal rootChain;
    TaskAuthorizationGate internal gate;

    bytes32 internal constant AGENT_ID = keccak256("emtun.agent.alpha");
    bytes32 internal constant UNREGISTERED_AGENT_ID = keccak256("emtun.agent.unregistered");
    bytes32 internal constant NEXT_ROOT = keccak256("policy.root.next");

    address internal owner = address(0xA11CE);

    function setUp() public {
        rootChain = new PolicyRootChain();
        HonkVerifier honkVerifier = new HonkVerifier();
        EmtunVerifierAdapter adapter = new EmtunVerifierAdapter(address(honkVerifier));

        registry = new AgentRegistry(address(rootChain));
        eas = new MockEAS();
        boundary = new EmtunEASAttestationBoundary(address(registry), address(eas));
        reader = new EmtunAuthorizationReader(address(rootChain), address(adapter));
        gate = new TaskAuthorizationGate(address(registry), address(boundary), address(reader));
    }

    function test_AuthorizesRegisteredAttestedCurrentRootAction() public {
        (bytes memory proof, bytes32 actionHash) = _registerAndAttestAgent();

        assertTrue(gate.isTaskAuthorized(AGENT_ID, proof, actionHash));
    }

    function test_RejectsUnregisteredAgent() public view {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();

        assertFalse(gate.isTaskAuthorized(UNREGISTERED_AGENT_ID, MerkleInclusionFixture.proof(), publicInputs[1]));
    }

    function test_RejectsRegisteredAgentWithoutActiveAttestation() public {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();

        vm.prank(owner);
        registry.registerAgent(AGENT_ID, publicInputs[0]);

        assertFalse(gate.isTaskAuthorized(AGENT_ID, MerkleInclusionFixture.proof(), publicInputs[1]));
    }

    function test_RejectsRevokedAttestation() public {
        (bytes memory proof, bytes32 actionHash) = _registerAndAttestAgent();

        vm.prank(owner);
        boundary.revokeAgentAttestation(AGENT_ID);

        assertFalse(gate.isTaskAuthorized(AGENT_ID, proof, actionHash));
    }

    function test_RejectsWrongActionHash() public {
        (bytes memory proof, bytes32 actionHash) = _registerAndAttestAgent();
        bytes32 wrongActionHash = bytes32(uint256(actionHash) + 1);

        assertFalse(gate.isTaskAuthorized(AGENT_ID, proof, wrongActionHash));
    }

    function test_RejectsStaleRootAfterRotationThroughAuthorizationReader() public {
        (bytes memory proof, bytes32 actionHash) = _registerAndAttestAgent();

        vm.prank(owner);
        rootChain.updateRoot(AGENT_ID, NEXT_ROOT);

        assertFalse(gate.isTaskAuthorized(AGENT_ID, proof, actionHash));
    }

    function test_RevertsWhenAgentRegistryIsNotContract() public {
        vm.expectRevert(TaskAuthorizationGate.InvalidAgentRegistry.selector);

        new TaskAuthorizationGate(address(0), address(boundary), address(reader));
    }

    function test_RevertsWhenAttestationBoundaryIsNotContract() public {
        vm.expectRevert(TaskAuthorizationGate.InvalidAttestationBoundary.selector);

        new TaskAuthorizationGate(address(registry), address(0), address(reader));
    }

    function test_RevertsWhenAuthorizationReaderIsNotContract() public {
        vm.expectRevert(TaskAuthorizationGate.InvalidAuthorizationReader.selector);

        new TaskAuthorizationGate(address(registry), address(boundary), address(0));
    }

    function _registerAndAttestAgent() private returns (bytes memory proof, bytes32 actionHash) {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();

        vm.startPrank(owner);
        registry.registerAgent(AGENT_ID, publicInputs[0]);
        boundary.attestAgent(AGENT_ID);
        vm.stopPrank();

        return (MerkleInclusionFixture.proof(), publicInputs[1]);
    }
}
