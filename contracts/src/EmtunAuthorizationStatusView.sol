// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AgentRegistry} from "./AgentRegistry.sol";
import {EmtunAuthorizationReader} from "./EmtunAuthorizationReader.sol";
import {EmtunEASAttestationBoundary} from "./EmtunEASAttestationBoundary.sol";

contract EmtunAuthorizationStatusView {
    struct AgentAuthorizationStatus {
        bool registered;
        bool activeAttestation;
        bool authorized;
        address owner;
        bytes32 policyRoot;
        uint64 registeredAt;
    }

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

    function getAgentAuthorizationStatus(bytes32 agentId, bytes calldata proof, bytes32 actionHash)
        external
        view
        returns (AgentAuthorizationStatus memory status)
    {
        if (!agentRegistry.isRegistered(agentId)) {
            return status;
        }

        status.registered = true;
        status.owner = agentRegistry.ownerOf(agentId);
        status.policyRoot = agentRegistry.currentPolicyRoot(agentId);
        status.registeredAt = agentRegistry.registeredAt(agentId);
        status.activeAttestation = attestationBoundary.hasActiveAgentAttestation(agentId);
        status.authorized = status.activeAttestation && authorizationReader.isAuthorized(agentId, proof, actionHash);
    }
}
