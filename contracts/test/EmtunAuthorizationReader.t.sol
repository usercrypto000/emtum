// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {EmtunAuthorizationReader} from "../src/EmtunAuthorizationReader.sol";
import {EmtunVerifierAdapter} from "../src/EmtunVerifierAdapter.sol";
import {PolicyRootChain} from "../src/PolicyRootChain.sol";
import {HonkVerifier} from "../src/verifiers/EmtunPolicyVerifier.sol";
import {MerkleInclusionFixture} from "./fixtures/MerkleInclusionFixture.sol";

contract EmtunAuthorizationReaderTest is Test {
    EmtunAuthorizationReader internal reader;
    EmtunVerifierAdapter internal adapter;
    HonkVerifier internal honkVerifier;
    PolicyRootChain internal rootChain;

    bytes32 internal constant AGENT_ID = keccak256("emtun.agent.alpha");
    bytes32 internal constant NEXT_ROOT = keccak256("policy.root.next");

    address internal controller = address(0xA11CE);

    function setUp() public {
        rootChain = new PolicyRootChain();
        honkVerifier = new HonkVerifier();
        adapter = new EmtunVerifierAdapter(address(honkVerifier));
        reader = new EmtunAuthorizationReader(address(rootChain), address(adapter));
    }

    function test_AuthorizesCurrentRootProof() public {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();

        vm.prank(controller);
        rootChain.openChain(AGENT_ID, publicInputs[0]);

        assertTrue(reader.isAuthorized(AGENT_ID, MerkleInclusionFixture.proof(), publicInputs[1]));
    }

    function test_RejectsProofAfterRootRotation() public {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();

        vm.startPrank(controller);
        rootChain.openChain(AGENT_ID, publicInputs[0]);
        rootChain.updateRoot(AGENT_ID, NEXT_ROOT);
        vm.stopPrank();

        assertFalse(reader.isAuthorized(AGENT_ID, MerkleInclusionFixture.proof(), publicInputs[1]));
    }

    function test_RejectsWrongActionHashAgainstCurrentRoot() public {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();
        bytes32 wrongActionHash = bytes32(uint256(publicInputs[1]) + 1);

        vm.prank(controller);
        rootChain.openChain(AGENT_ID, publicInputs[0]);

        assertFalse(reader.isAuthorized(AGENT_ID, MerkleInclusionFixture.proof(), wrongActionHash));
    }

    function test_RejectsUnopenedChain() public view {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();

        assertFalse(reader.isAuthorized(AGENT_ID, MerkleInclusionFixture.proof(), publicInputs[1]));
    }

    function test_RejectsMalformedProof() public {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();

        vm.prank(controller);
        rootChain.openChain(AGENT_ID, publicInputs[0]);

        assertFalse(reader.isAuthorized(AGENT_ID, hex"01", publicInputs[1]));
    }

    function test_RevertsWhenPolicyRootChainIsNotContract() public {
        vm.expectRevert(EmtunAuthorizationReader.InvalidPolicyRootChain.selector);

        new EmtunAuthorizationReader(address(0), address(adapter));
    }

    function test_RevertsWhenVerifierAdapterIsNotContract() public {
        vm.expectRevert(EmtunAuthorizationReader.InvalidVerifierAdapter.selector);

        new EmtunAuthorizationReader(address(rootChain), address(0));
    }

    function test_Gas_AuthorizesThroughReader() public {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();

        vm.prank(controller);
        rootChain.openChain(AGENT_ID, publicInputs[0]);

        uint256 gasBefore = gasleft();
        bool authorized = reader.isAuthorized(AGENT_ID, MerkleInclusionFixture.proof(), publicInputs[1]);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("reader authorization gas", gasUsed);
        assertTrue(authorized);
    }
}
