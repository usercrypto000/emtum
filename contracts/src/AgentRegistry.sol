// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PolicyRootChain} from "./PolicyRootChain.sol";

contract AgentRegistry {
    struct AgentRecord {
        address owner;
        uint64 registeredAt;
    }

    error InvalidPolicyRootChain();
    error InvalidAgentId();
    error InvalidOwner();
    error InvalidRoot();
    error AgentAlreadyRegistered(bytes32 agentId);
    error AgentNotRegistered(bytes32 agentId);
    error NotAgentOwner(bytes32 agentId, address caller);

    event AgentRegistered(bytes32 indexed agentId, address indexed owner, bytes32 indexed initialPolicyRoot);
    event AgentOwnerTransferred(bytes32 indexed agentId, address indexed previousOwner, address indexed newOwner);

    PolicyRootChain public immutable policyRootChain;

    mapping(bytes32 agentId => AgentRecord record) private agents;

    constructor(address policyRootChain_) {
        if (policyRootChain_.code.length == 0) {
            revert InvalidPolicyRootChain();
        }

        policyRootChain = PolicyRootChain(policyRootChain_);
    }

    function registerAgent(bytes32 agentId, bytes32 initialPolicyRoot) external {
        if (agentId == bytes32(0)) {
            revert InvalidAgentId();
        }

        if (initialPolicyRoot == bytes32(0)) {
            revert InvalidRoot();
        }

        if (agents[agentId].owner != address(0)) {
            revert AgentAlreadyRegistered(agentId);
        }

        agents[agentId] = AgentRecord({owner: msg.sender, registeredAt: uint64(block.timestamp)});

        policyRootChain.openChain(agentId, initialPolicyRoot);
        policyRootChain.transferController(agentId, msg.sender);

        emit AgentRegistered(agentId, msg.sender, initialPolicyRoot);
    }

    function transferAgentOwner(bytes32 agentId, address newOwner) external {
        AgentRecord storage record = _agent(agentId);

        if (msg.sender != record.owner) {
            revert NotAgentOwner(agentId, msg.sender);
        }

        if (newOwner == address(0)) {
            revert InvalidOwner();
        }

        address previousOwner = record.owner;
        record.owner = newOwner;

        emit AgentOwnerTransferred(agentId, previousOwner, newOwner);
    }

    function isRegistered(bytes32 agentId) external view returns (bool) {
        return agents[agentId].owner != address(0);
    }

    function ownerOf(bytes32 agentId) external view returns (address) {
        return _agent(agentId).owner;
    }

    function registeredAt(bytes32 agentId) external view returns (uint64) {
        return _agent(agentId).registeredAt;
    }

    function currentPolicyRoot(bytes32 agentId) external view returns (bytes32) {
        _agent(agentId);

        return policyRootChain.currentRoot(agentId);
    }

    function policyControllerOf(bytes32 agentId) external view returns (address) {
        _agent(agentId);

        return policyRootChain.controllerOf(agentId);
    }

    function _agent(bytes32 agentId) private view returns (AgentRecord storage record) {
        record = agents[agentId];

        if (record.owner == address(0)) {
            revert AgentNotRegistered(agentId);
        }
    }
}
