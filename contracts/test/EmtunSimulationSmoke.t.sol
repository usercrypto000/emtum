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

contract EmtunSimulationSmokeTest is Test {
    AgentRegistry internal registry;
    EmtunEASAttestationBoundary internal boundary;
    MockEAS internal eas;
    PolicyRootChain internal rootChain;
    TaskAuthorizationGate internal gate;

    bytes32 internal constant AGENT_ID = keccak256("emtun.agent.alpha");
    bytes32 internal constant NEXT_ROOT = keccak256("policy.root.next");

    address internal owner = address(0xA11CE);
    address internal nextOwner = address(0xB0B);

    function setUp() public {
        rootChain = new PolicyRootChain();
        HonkVerifier honkVerifier = new HonkVerifier();
        EmtunVerifierAdapter adapter = new EmtunVerifierAdapter(address(honkVerifier));
        EmtunAuthorizationReader reader = new EmtunAuthorizationReader(address(rootChain), address(adapter));

        registry = new AgentRegistry(address(rootChain));
        eas = new MockEAS();
        boundary = new EmtunEASAttestationBoundary(address(registry), address(eas));
        gate = new TaskAuthorizationGate(address(registry), address(boundary), address(reader));
    }

    function test_FullAuthorizationLifecycleSmoke() public {
        bytes memory proof = MerkleInclusionFixture.proof();
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();
        bytes32 policyRoot = publicInputs[0];
        bytes32 actionHash = publicInputs[1];

        emit log_named_bytes32("policy_root", policyRoot);
        emit log_named_bytes32("action_hash", actionHash);

        vm.prank(owner);
        registry.registerAgent(AGENT_ID, policyRoot);
        emit log("REGISTERED AGENT");

        vm.prank(owner);
        bytes32 firstUid = boundary.attestAgent(AGENT_ID);
        emit log_named_bytes32("identity_attestation_uid", firstUid);

        assertTrue(gate.isTaskAuthorized(AGENT_ID, proof, actionHash));
        emit log("CURRENT ROOT AUTHORIZATION CONFIRMED");

        vm.prank(owner);
        rootChain.updateRoot(AGENT_ID, NEXT_ROOT);
        assertFalse(gate.isTaskAuthorized(AGENT_ID, proof, actionHash));
        emit log("STALE ROOT REJECTION CONFIRMED");

        vm.prank(owner);
        rootChain.updateRoot(AGENT_ID, policyRoot);
        assertTrue(gate.isTaskAuthorized(AGENT_ID, proof, actionHash));
        emit log("CHAIN HEAD REAUTHORIZATION CONFIRMED");

        vm.prank(owner);
        registry.transferAgentOwner(AGENT_ID, nextOwner);
        assertFalse(boundary.hasActiveAgentAttestation(AGENT_ID));
        assertFalse(gate.isTaskAuthorized(AGENT_ID, proof, actionHash));
        emit log("OWNER TRANSFER ATTESTATION INVALIDATION CONFIRMED");

        vm.prank(nextOwner);
        bytes32 secondUid = boundary.attestAgent(AGENT_ID);
        assertTrue(gate.isTaskAuthorized(AGENT_ID, proof, actionHash));
        emit log_named_bytes32("new_owner_attestation_uid", secondUid);
        emit log("EMTUN FULL SIMULATION CONFIRMED");
    }
}
