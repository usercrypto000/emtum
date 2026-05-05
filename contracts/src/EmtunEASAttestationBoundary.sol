// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IAgentRegistryReader} from "./interfaces/IAgentRegistryReader.sol";
import {IMockEAS} from "./interfaces/IMockEAS.sol";

contract EmtunEASAttestationBoundary {
    bytes32 public constant AGENT_IDENTITY_SCHEMA = keccak256("Emtun.Agent.Identity.v1");

    error InvalidAgentRegistry();
    error InvalidEAS();
    error InvalidAgentId();
    error NotAgentOwner(bytes32 agentId, address caller);
    error AttestationAlreadyActive(bytes32 agentId, bytes32 uid);
    error NoActiveAttestation(bytes32 agentId);

    event AgentIdentityAttested(
        bytes32 indexed agentId,
        address indexed owner,
        bytes32 indexed uid,
        address agentRegistry,
        address policyRootChain
    );
    event AgentIdentityRevoked(bytes32 indexed agentId, address indexed owner, bytes32 indexed uid);

    IAgentRegistryReader public immutable agentRegistry;
    IMockEAS public immutable eas;

    mapping(bytes32 agentId => bytes32 uid) public activeAttestationUid;
    mapping(bytes32 agentId => address owner) public attestedOwner;

    constructor(address agentRegistry_, address eas_) {
        if (agentRegistry_.code.length == 0) {
            revert InvalidAgentRegistry();
        }

        if (eas_.code.length == 0) {
            revert InvalidEAS();
        }

        agentRegistry = IAgentRegistryReader(agentRegistry_);
        eas = IMockEAS(eas_);
    }

    function attestAgent(bytes32 agentId) external returns (bytes32 uid) {
        if (agentId == bytes32(0)) {
            revert InvalidAgentId();
        }

        address owner = agentRegistry.ownerOf(agentId);

        if (msg.sender != owner) {
            revert NotAgentOwner(agentId, msg.sender);
        }

        bytes32 existingUid = activeAttestationUid[agentId];

        if (existingUid != bytes32(0) && eas.isAttestationActive(existingUid) && attestedOwner[agentId] == owner) {
            revert AttestationAlreadyActive(agentId, existingUid);
        }

        address policyRootChain = agentRegistry.policyRootChain();
        bytes memory data = abi.encode(agentId, address(agentRegistry), policyRootChain);

        uid = eas.attest(AGENT_IDENTITY_SCHEMA, owner, data);
        activeAttestationUid[agentId] = uid;
        attestedOwner[agentId] = owner;

        emit AgentIdentityAttested(agentId, owner, uid, address(agentRegistry), policyRootChain);
    }

    function revokeAgentAttestation(bytes32 agentId) external {
        bytes32 uid = activeAttestationUid[agentId];

        if (uid == bytes32(0) || !eas.isAttestationActive(uid)) {
            revert NoActiveAttestation(agentId);
        }

        address owner = agentRegistry.ownerOf(agentId);

        if (msg.sender != owner) {
            revert NotAgentOwner(agentId, msg.sender);
        }

        eas.revoke(uid);
        activeAttestationUid[agentId] = bytes32(0);
        attestedOwner[agentId] = address(0);

        emit AgentIdentityRevoked(agentId, owner, uid);
    }

    function hasActiveAgentAttestation(bytes32 agentId) external view returns (bool) {
        bytes32 uid = activeAttestationUid[agentId];

        return
            uid != bytes32(0) && eas.isAttestationActive(uid)
                && attestedOwner[agentId] == agentRegistry.ownerOf(agentId);
    }
}
