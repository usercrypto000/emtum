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

contract PrimitiveBoundarySmokeTest is Test {
    AgentRegistry internal registry;
    EmtunEASAttestationBoundary internal boundary;
    EmtunAuthorizationStatusView internal statusView;
    PolicyRootChain internal rootChain;

    bytes32 internal constant AGENT_ID = keccak256("emtun.agent.alpha");

    address internal owner = address(0xA11CE);

    function setUp() public {
        rootChain = new PolicyRootChain();
        HonkVerifier honkVerifier = new HonkVerifier();
        EmtunVerifierAdapter adapter = new EmtunVerifierAdapter(address(honkVerifier));
        EmtunAuthorizationReader reader = new EmtunAuthorizationReader(address(rootChain), address(adapter));

        registry = new AgentRegistry(address(rootChain));
        MockEAS eas = new MockEAS();
        boundary = new EmtunEASAttestationBoundary(address(registry), address(eas));
        statusView = new EmtunAuthorizationStatusView(address(registry), address(boundary), address(reader));
    }

    function test_PrimitiveBoundarySmoke() public {
        bytes memory proof = MerkleInclusionFixture.proof();
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();
        bytes32 policyRoot = publicInputs[0];
        bytes32 actionHash = publicInputs[1];

        vm.startPrank(owner);
        registry.registerAgent(AGENT_ID, policyRoot);
        boundary.attestAgent(AGENT_ID);
        vm.stopPrank();

        EmtunAuthorizationStatusView.AgentAuthorizationStatus memory status =
            statusView.getAgentAuthorizationStatus(AGENT_ID, proof, actionHash);

        assertTrue(status.registered);
        assertTrue(status.activeAttestation);
        assertTrue(status.authorized);
        assertEq(status.policyRoot, policyRoot);

        emit log_named_bytes32("policy_root", policyRoot);
        emit log_named_bytes32("action_hash", actionHash);
        emit log("SAP PUBLIC INPUTS CONFIRMED");
        emit log("SAP AUTHORIZATION STATUS CONFIRMED");
        emit log("EXECUTION CORRECTNESS OUT OF SCOPE");
    }
}
