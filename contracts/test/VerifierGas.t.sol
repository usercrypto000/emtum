// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {HonkVerifier} from "../src/verifiers/EmtunPolicyVerifier.sol";
import {MerkleInclusionFixture} from "./fixtures/MerkleInclusionFixture.sol";

contract VerifierGasTest is Test {
    HonkVerifier internal verifier;

    function setUp() public {
        verifier = new HonkVerifier();
    }

    function test_VerifiesMerkleInclusionProof() public view {
        assertTrue(verifier.verify(MerkleInclusionFixture.proof(), MerkleInclusionFixture.publicInputs()));
    }

    function test_Gas_VerifyMerkleInclusionProof() public {
        uint256 gasBefore = gasleft();
        bool verified = verifier.verify(MerkleInclusionFixture.proof(), MerkleInclusionFixture.publicInputs());
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("single proof verification gas", gasUsed);
        assertTrue(verified);
    }
}
