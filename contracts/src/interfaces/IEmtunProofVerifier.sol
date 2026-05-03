// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IEmtunProofVerifier {
    function verify(bytes calldata proof, bytes32[] calldata publicInputs) external view returns (bool);
}
