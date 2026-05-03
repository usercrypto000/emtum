// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {EmtunEASAttestationBoundary} from "../src/EmtunEASAttestationBoundary.sol";
import {MockEAS} from "../src/MockEAS.sol";
import {PolicyRootChain} from "../src/PolicyRootChain.sol";

contract EmtunEASAttestationBoundaryTest is Test {
    AgentRegistry internal registry;
    EmtunEASAttestationBoundary internal boundary;
    MockEAS internal eas;
    PolicyRootChain internal rootChain;

    bytes32 internal constant AGENT_ID = keccak256("emtun.agent.alpha");
    bytes32 internal constant INITIAL_ROOT = keccak256("policy.root.initial");
    bytes32 internal constant NEXT_ROOT = keccak256("policy.root.next");

    address internal owner = address(0xA11CE);
    address internal attacker = address(0xBAD);

    function setUp() public {
        rootChain = new PolicyRootChain();
        registry = new AgentRegistry(address(rootChain));
        eas = new MockEAS();
        boundary = new EmtunEASAttestationBoundary(address(registry), address(eas));

        vm.prank(owner);
        registry.registerAgent(AGENT_ID, INITIAL_ROOT);
    }

    function test_AttestsRegisteredAgentIdentityToChainHead() public {
        vm.prank(owner);
        bytes32 uid = boundary.attestAgent(AGENT_ID);

        MockEAS.Attestation memory attestation = eas.getAttestation(uid);
        (bytes32 attestedAgentId, address attestedRegistry, address attestedRootChain) =
            abi.decode(attestation.data, (bytes32, address, address));

        assertTrue(eas.isAttestationActive(uid));
        assertTrue(boundary.hasActiveAgentAttestation(AGENT_ID));
        assertEq(boundary.activeAttestationUid(AGENT_ID), uid);
        assertEq(attestation.schema, boundary.AGENT_IDENTITY_SCHEMA());
        assertEq(attestation.recipient, owner);
        assertEq(attestation.attester, address(boundary));
        assertEq(attestedAgentId, AGENT_ID);
        assertEq(attestedRegistry, address(registry));
        assertEq(attestedRootChain, address(rootChain));
    }

    function test_AttestationSurvivesPolicyRootRotation() public {
        vm.prank(owner);
        bytes32 uid = boundary.attestAgent(AGENT_ID);

        vm.prank(owner);
        rootChain.updateRoot(AGENT_ID, NEXT_ROOT);

        MockEAS.Attestation memory attestation = eas.getAttestation(uid);
        (bytes32 attestedAgentId, address attestedRegistry, address attestedRootChain) =
            abi.decode(attestation.data, (bytes32, address, address));

        assertTrue(eas.isAttestationActive(uid));
        assertTrue(boundary.hasActiveAgentAttestation(AGENT_ID));
        assertEq(rootChain.currentRoot(AGENT_ID), NEXT_ROOT);
        assertEq(attestedAgentId, AGENT_ID);
        assertEq(attestedRegistry, address(registry));
        assertEq(attestedRootChain, address(rootChain));
    }

    function test_OnlyAgentOwnerCanAttest() public {
        vm.expectRevert(abi.encodeWithSelector(EmtunEASAttestationBoundary.NotAgentOwner.selector, AGENT_ID, attacker));
        vm.prank(attacker);
        boundary.attestAgent(AGENT_ID);
    }

    function test_RevertsWhenAttestationAlreadyActive() public {
        vm.startPrank(owner);
        bytes32 uid = boundary.attestAgent(AGENT_ID);
        vm.expectRevert(abi.encodeWithSelector(EmtunEASAttestationBoundary.AttestationAlreadyActive.selector, AGENT_ID, uid));
        boundary.attestAgent(AGENT_ID);
        vm.stopPrank();
    }

    function test_OwnerCanRevokeActiveAttestation() public {
        vm.startPrank(owner);
        bytes32 uid = boundary.attestAgent(AGENT_ID);
        boundary.revokeAgentAttestation(AGENT_ID);
        vm.stopPrank();

        assertFalse(eas.isAttestationActive(uid));
        assertFalse(boundary.hasActiveAgentAttestation(AGENT_ID));
        assertEq(boundary.activeAttestationUid(AGENT_ID), bytes32(0));
    }

    function test_CanReattestAfterRevocation() public {
        vm.startPrank(owner);
        bytes32 firstUid = boundary.attestAgent(AGENT_ID);
        boundary.revokeAgentAttestation(AGENT_ID);
        bytes32 secondUid = boundary.attestAgent(AGENT_ID);
        vm.stopPrank();

        assertFalse(eas.isAttestationActive(firstUid));
        assertTrue(eas.isAttestationActive(secondUid));
        assertEq(boundary.activeAttestationUid(AGENT_ID), secondUid);
    }

    function test_OnlyAgentOwnerCanRevoke() public {
        vm.prank(owner);
        boundary.attestAgent(AGENT_ID);

        vm.expectRevert(abi.encodeWithSelector(EmtunEASAttestationBoundary.NotAgentOwner.selector, AGENT_ID, attacker));
        vm.prank(attacker);
        boundary.revokeAgentAttestation(AGENT_ID);
    }

    function test_RevertsWhenNoActiveAttestationExists() public {
        vm.expectRevert(abi.encodeWithSelector(EmtunEASAttestationBoundary.NoActiveAttestation.selector, AGENT_ID));
        vm.prank(owner);
        boundary.revokeAgentAttestation(AGENT_ID);
    }

    function test_RevertsOnZeroAgentId() public {
        vm.expectRevert(EmtunEASAttestationBoundary.InvalidAgentId.selector);
        boundary.attestAgent(bytes32(0));
    }

    function test_RevertsWhenAgentRegistryIsNotContract() public {
        vm.expectRevert(EmtunEASAttestationBoundary.InvalidAgentRegistry.selector);
        new EmtunEASAttestationBoundary(address(0), address(eas));
    }

    function test_RevertsWhenEASIsNotContract() public {
        vm.expectRevert(EmtunEASAttestationBoundary.InvalidEAS.selector);
        new EmtunEASAttestationBoundary(address(registry), address(0));
    }
}
