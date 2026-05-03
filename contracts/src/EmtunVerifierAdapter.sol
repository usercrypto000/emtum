// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IEmtunProofVerifier} from "./interfaces/IEmtunProofVerifier.sol";

contract EmtunVerifierAdapter {
    error InvalidVerifier();

    uint256 public constant PUBLIC_INPUT_COUNT = 2;

    IEmtunProofVerifier public immutable verifier;

    constructor(address verifier_) {
        if (verifier_.code.length == 0) {
            revert InvalidVerifier();
        }

        verifier = IEmtunProofVerifier(verifier_);
    }

    function verifyAuthorization(bytes calldata proof, bytes32 policyRoot, bytes32 actionHash)
        external
        view
        returns (bool)
    {
        bytes32[] memory publicInputs = new bytes32[](PUBLIC_INPUT_COUNT);
        publicInputs[0] = policyRoot;
        publicInputs[1] = actionHash;

        (bool ok, bytes memory result) =
            address(verifier).staticcall(abi.encodeCall(IEmtunProofVerifier.verify, (proof, publicInputs)));

        if (!ok || result.length != 32) {
            return false;
        }

        return abi.decode(result, (bool));
    }
}
