// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PolicyRootChainHead} from "../src/PolicyRootChainHead.sol";
import {EmtunVerifierAdapter} from "../src/EmtunVerifierAdapter.sol";
import {HonkVerifier} from "../src/verifiers/EmtunPolicyVerifier.sol";
import {MerkleInclusionFixture} from "./fixtures/MerkleInclusionFixture.sol";

contract E2E_PolicyRootChainHead_VerificationTest is Test {
    PolicyRootChainHead internal chainHead;
    EmtunVerifierAdapter internal adapter;
    HonkVerifier internal verifier;

    address internal agent = address(0xA11CE);
    address internal controller = address(0xB0B);

    function setUp() public {
        chainHead = new PolicyRootChainHead();
        verifier = new HonkVerifier();
        adapter = new EmtunVerifierAdapter(address(verifier));

        // Register agent and controller
        chainHead.registerAgent(agent, controller);
    }

    function test_E2E_FullLifecycle_Advance_Verify_Revoke() public {
        bytes32[] memory publicInputs = MerkleInclusionFixture.publicInputs();
        bytes memory proof = MerkleInclusionFixture.proof();

        bytes32 policyRoot = publicInputs[0];
        bytes32 actionHash = publicInputs[1];

        // Step 1: Controller advances policy root head on-chain
        vm.prank(controller);
        chainHead.advanceRoot(agent, policyRoot);

        (bytes32 currentRoot, uint256 versionNonce, ) = chainHead.getRootPointer(agent);
        assertEq(currentRoot, policyRoot);
        assertEq(versionNonce, 1);

        // Step 2: Verifier staticcall using the current policy root from chain head
        bool verified = adapter.verifyAuthorization(proof, currentRoot, actionHash);
        assertTrue(verified, "ZK proof verification failed against active policy root.");

        // Step 3: Emergency Instant Revocation
        vm.prank(controller);
        chainHead.revokeRoot(agent);

        (bytes32 revokedRoot, uint256 revokedNonce, ) = chainHead.getRootPointer(agent);
        assertEq(revokedRoot, bytes32(0));
        assertEq(revokedNonce, 2);

        // Step 4: Verification targeting the revoked zero-root fails immediately
        bool verifyAfterRevocation = adapter.verifyAuthorization(proof, revokedRoot, actionHash);
        assertFalse(verifyAfterRevocation, "Proof verification must fail after root revocation.");
    }
}
