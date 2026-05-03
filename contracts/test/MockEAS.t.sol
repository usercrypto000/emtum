// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {MockEAS} from "../src/MockEAS.sol";

contract MockEASTest is Test {
    MockEAS internal eas;

    bytes32 internal constant SCHEMA = keccak256("schema");
    address internal recipient = address(0xA11CE);
    address internal attacker = address(0xBAD);

    function setUp() public {
        eas = new MockEAS();
    }

    function test_AttestStoresRecord() public {
        bytes memory data = abi.encode("payload");

        bytes32 uid = eas.attest(SCHEMA, recipient, data);
        MockEAS.Attestation memory attestation = eas.getAttestation(uid);

        assertTrue(eas.isAttestationActive(uid));
        assertEq(attestation.uid, uid);
        assertEq(attestation.schema, SCHEMA);
        assertEq(attestation.recipient, recipient);
        assertEq(attestation.attester, address(this));
        assertEq(attestation.data, data);
    }

    function test_OnlyAttesterCanRevoke() public {
        bytes32 uid = eas.attest(SCHEMA, recipient, "");

        vm.expectRevert(abi.encodeWithSelector(MockEAS.NotAttester.selector, uid, attacker));
        vm.prank(attacker);
        eas.revoke(uid);
    }

    function test_RevokeDeactivatesAttestation() public {
        bytes32 uid = eas.attest(SCHEMA, recipient, "");

        eas.revoke(uid);

        assertFalse(eas.isAttestationActive(uid));
    }
}
