// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AgentRegistry} from "./AgentRegistry.sol";
import {EmtunAuthorizationReader} from "./EmtunAuthorizationReader.sol";
import {EmtunEASAttestationBoundary} from "./EmtunEASAttestationBoundary.sol";

contract TaskAuthorizationGate {
    error InvalidAgentRegistry();
    error InvalidAttestationBoundary();
    error InvalidAuthorizationReader();

    AgentRegistry public immutable agentRegistry;
    EmtunEASAttestationBoundary public immutable attestationBoundary;
    EmtunAuthorizationReader public immutable authorizationReader;

    constructor(address agentRegistry_, address attestationBoundary_, address authorizationReader_) {
        if (agentRegistry_.code.length == 0) {
            revert InvalidAgentRegistry();
        }

        if (attestationBoundary_.code.length == 0) {
            revert InvalidAttestationBoundary();
        }

        if (authorizationReader_.code.length == 0) {
            revert InvalidAuthorizationReader();
        }

        agentRegistry = AgentRegistry(agentRegistry_);
        attestationBoundary = EmtunEASAttestationBoundary(attestationBoundary_);
        authorizationReader = EmtunAuthorizationReader(authorizationReader_);
    }

    function isTaskAuthorized(bytes32 agentId, bytes calldata proof, bytes32 actionHash) external view returns (bool) {
        return agentRegistry.isRegistered(agentId) && attestationBoundary.hasActiveAgentAttestation(agentId)
            && authorizationReader.isAuthorized(agentId, proof, actionHash);
    }
}
