// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract PolicyRootChainHead {
    struct RootPointer {
        bytes32 currentRoot;
        uint256 versionNonce;
        uint256 updatedAt;
    }

    error AgentAlreadyRegistered();
    error NotAgentController();
    error InvalidRoot();
    error InvalidController();
    error AgentNotRegistered();

    event AgentRegistered(address indexed agent, address indexed controller);
    event RootAdvanced(address indexed agent, bytes32 indexed newRoot, uint256 indexed versionNonce);
    event RootRevoked(address indexed agent, uint256 indexed versionNonce);

    // Maps agent address (ERC-8004 identity) to its root state
    mapping(address => RootPointer) private registry;
    // Maps agent address to its designated owner/controller
    mapping(address => address) private controllers;

    function registerAgent(address agent, address controller) external {
        if (controller == address(0)) revert InvalidController();
        if (controllers[agent] != address(0)) revert AgentAlreadyRegistered();
        
        controllers[agent] = controller;
        emit AgentRegistered(agent, controller);
    }

    function advanceRoot(address agent, bytes32 newRoot) external {
        address controller = controllers[agent];
        if (controller == address(0)) revert AgentNotRegistered();
        if (msg.sender != controller) revert NotAgentController();
        if (newRoot == bytes32(0)) revert InvalidRoot();

        RootPointer storage pointer = registry[agent];
        pointer.currentRoot = newRoot;
        pointer.versionNonce += 1;
        pointer.updatedAt = block.timestamp;

        emit RootAdvanced(agent, newRoot, pointer.versionNonce);
    }

    function revokeRoot(address agent) external {
        address controller = controllers[agent];
        if (controller == address(0)) revert AgentNotRegistered();
        if (msg.sender != controller) revert NotAgentController();

        RootPointer storage pointer = registry[agent];
        pointer.currentRoot = bytes32(0);
        pointer.versionNonce += 1;
        pointer.updatedAt = block.timestamp;

        emit RootRevoked(agent, pointer.versionNonce);
    }

    function getRootPointer(address agent) external view returns (bytes32 currentRoot, uint256 versionNonce, uint256 updatedAt) {
        RootPointer memory pointer = registry[agent];
        return (pointer.currentRoot, pointer.versionNonce, pointer.updatedAt);
    }

    function getController(address agent) external view returns (address) {
        return controllers[agent];
    }
}
