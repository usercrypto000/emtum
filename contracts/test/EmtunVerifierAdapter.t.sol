// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {EmtunVerifierAdapter} from "../src/EmtunVerifierAdapter.sol";
import {HonkVerifier} from "../src/verifiers/EmtunPolicyVerifier.sol";
import {MerkleInclusionFixture} from "./fixtures/MerkleInclusionFixture.sol";

contract EmtunVerifierAdapterTest is Test {
    HonkVerifier internal honkVerifier;
    EmtunVerifierAdapter internal adapter;

    function setUp() public {
        honkVerifier = new HonkVerifier();
        adapter = new EmtunVerifierAdapter(address(honkVerifier));
    }

    function test_VerifiesFixtureThroughAdapter() public view {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();

        assertTrue(adapter.verifyAuthorization(MerkleInclusionFixture.proof(), publicInputs[0], publicInputs[1]));
    }

    function test_RejectsWrongPolicyRoot() public view {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();
        bytes32 wrongPolicyRoot = bytes32(uint256(publicInputs[0]) + 1);

        assertFalse(adapter.verifyAuthorization(MerkleInclusionFixture.proof(), wrongPolicyRoot, publicInputs[1]));
    }

    function test_RejectsWrongActionHash() public view {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();
        bytes32 wrongActionHash = bytes32(uint256(publicInputs[1]) + 1);

        assertFalse(adapter.verifyAuthorization(MerkleInclusionFixture.proof(), publicInputs[0], wrongActionHash));
    }

    function test_RejectsMalformedProof() public view {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();

        assertFalse(adapter.verifyAuthorization(hex"01", publicInputs[0], publicInputs[1]));
    }

    function test_RevertsWhenVerifierIsNotContract() public {
        vm.expectRevert(EmtunVerifierAdapter.InvalidVerifier.selector);

        new EmtunVerifierAdapter(address(0));
    }

    function test_Gas_VerifyAuthorizationThroughAdapter() public {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();

        uint256 gasBefore = gasleft();
        bool verified = adapter.verifyAuthorization(MerkleInclusionFixture.proof(), publicInputs[0], publicInputs[1]);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("adapter authorization verification gas", gasUsed);
        assertTrue(verified);
    }
}
