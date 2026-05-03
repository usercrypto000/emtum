// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {EmtunAuthorizationReader} from "../src/EmtunAuthorizationReader.sol";
import {EmtunVerifierAdapter} from "../src/EmtunVerifierAdapter.sol";
import {PolicyRootChain} from "../src/PolicyRootChain.sol";
import {HonkVerifier} from "../src/verifiers/EmtunPolicyVerifier.sol";
import {MerkleInclusionFixture} from "./fixtures/MerkleInclusionFixture.sol";

contract EmtunSapFlowTest is Test {
    AgentRegistry internal registry;
    EmtunAuthorizationReader internal reader;
    PolicyRootChain internal rootChain;

    bytes32 internal constant AGENT_ID = keccak256("emtun.agent.alpha");
    bytes32 internal constant NEXT_ROOT = keccak256("policy.root.next");

    address internal owner = address(0xA11CE);

    function setUp() public {
        rootChain = new PolicyRootChain();
        HonkVerifier honkVerifier = new HonkVerifier();
        EmtunVerifierAdapter adapter = new EmtunVerifierAdapter(address(honkVerifier));

        registry = new AgentRegistry(address(rootChain));
        reader = new EmtunAuthorizationReader(address(rootChain), address(adapter));
    }

    function test_RegisteredAgentCanAuthorizeCurrentRootAction() public {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();

        vm.prank(owner);
        registry.registerAgent(AGENT_ID, publicInputs[0]);

        assertTrue(reader.isAuthorized(AGENT_ID, MerkleInclusionFixture.proof(), publicInputs[1]));
    }

    function test_RegisteredAgentRejectsOldProofAfterPolicyRootUpdate() public {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();

        vm.startPrank(owner);
        registry.registerAgent(AGENT_ID, publicInputs[0]);
        rootChain.updateRoot(AGENT_ID, NEXT_ROOT);
        vm.stopPrank();

        assertFalse(reader.isAuthorized(AGENT_ID, MerkleInclusionFixture.proof(), publicInputs[1]));
    }
}
