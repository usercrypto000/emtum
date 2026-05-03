// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IMockEAS {
    function attest(bytes32 schema, address recipient, bytes calldata data) external returns (bytes32);
    function revoke(bytes32 uid) external;
    function isAttestationActive(bytes32 uid) external view returns (bool);
}
