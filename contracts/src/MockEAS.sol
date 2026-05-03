// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract MockEAS {
    struct Attestation {
        bytes32 uid;
        bytes32 schema;
        address recipient;
        address attester;
        uint64 time;
        bool revoked;
        bytes data;
    }

    error InvalidSchema();
    error InvalidRecipient();
    error AttestationNotFound(bytes32 uid);
    error NotAttester(bytes32 uid, address caller);
    error AttestationAlreadyRevoked(bytes32 uid);

    event Attested(bytes32 indexed uid, bytes32 indexed schema, address indexed recipient, address attester);
    event Revoked(bytes32 indexed uid, address indexed revoker);

    uint64 public nonce;

    mapping(bytes32 uid => Attestation attestation) private attestations;

    function attest(bytes32 schema, address recipient, bytes calldata data) external returns (bytes32 uid) {
        if (schema == bytes32(0)) {
            revert InvalidSchema();
        }

        if (recipient == address(0)) {
            revert InvalidRecipient();
        }

        uid = keccak256(abi.encode(address(this), block.chainid, nonce, msg.sender, schema, recipient, data));
        nonce += 1;

        attestations[uid] = Attestation({
            uid: uid,
            schema: schema,
            recipient: recipient,
            attester: msg.sender,
            time: uint64(block.timestamp),
            revoked: false,
            data: data
        });

        emit Attested(uid, schema, recipient, msg.sender);
    }

    function revoke(bytes32 uid) external {
        Attestation storage attestation = _attestation(uid);

        if (msg.sender != attestation.attester) {
            revert NotAttester(uid, msg.sender);
        }

        if (attestation.revoked) {
            revert AttestationAlreadyRevoked(uid);
        }

        attestation.revoked = true;

        emit Revoked(uid, msg.sender);
    }

    function getAttestation(bytes32 uid) external view returns (Attestation memory) {
        return _attestation(uid);
    }

    function isAttestationActive(bytes32 uid) external view returns (bool) {
        Attestation storage attestation = attestations[uid];

        return attestation.uid != bytes32(0) && !attestation.revoked;
    }

    function _attestation(bytes32 uid) private view returns (Attestation storage attestation) {
        attestation = attestations[uid];

        if (attestation.uid == bytes32(0)) {
            revert AttestationNotFound(uid);
        }
    }
}
