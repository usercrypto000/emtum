// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IEmtunAuthorizationVerifier} from "./interfaces/IEmtunAuthorizationVerifier.sol";
import {IPolicyRootReader} from "./interfaces/IPolicyRootReader.sol";

contract EmtunAuthorizationReader {
    error InvalidPolicyRootChain();
    error InvalidVerifierAdapter();

    IPolicyRootReader public immutable policyRootChain;
    IEmtunAuthorizationVerifier public immutable verifierAdapter;

    constructor(address policyRootChain_, address verifierAdapter_) {
        if (policyRootChain_.code.length == 0) {
            revert InvalidPolicyRootChain();
        }

        if (verifierAdapter_.code.length == 0) {
            revert InvalidVerifierAdapter();
        }

        policyRootChain = IPolicyRootReader(policyRootChain_);
        verifierAdapter = IEmtunAuthorizationVerifier(verifierAdapter_);
    }

    function isAuthorized(bytes32 agentId, bytes calldata proof, bytes32 actionHash) external view returns (bool) {
        (bool rootResolved, bytes memory rootResult) =
            address(policyRootChain).staticcall(abi.encodeCall(IPolicyRootReader.currentRoot, (agentId)));

        if (!rootResolved || rootResult.length != 32) {
            return false;
        }

        bytes32 policyRoot = abi.decode(rootResult, (bytes32));
        (bool verified, bytes memory verifierResult) = address(verifierAdapter).staticcall(
            abi.encodeCall(IEmtunAuthorizationVerifier.verifyAuthorization, (proof, policyRoot, actionHash))
        );

        if (!verified || verifierResult.length != 32) {
            return false;
        }

        return abi.decode(verifierResult, (bool));
    }
}
