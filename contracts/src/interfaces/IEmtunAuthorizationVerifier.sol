// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IEmtunAuthorizationVerifier {
    function verifyAuthorization(bytes calldata proof, bytes32 policyRoot, bytes32 actionHash)
        external
        view
        returns (bool);
}
