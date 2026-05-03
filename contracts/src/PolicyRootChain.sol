// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract PolicyRootChain {
    struct RootRecord {
        bytes32 root;
        bytes32 previousRoot;
        uint64 version;
        uint64 updatedAt;
    }

    struct ChainState {
        address controller;
        RootRecord current;
    }

    error InvalidAgentId();
    error InvalidController();
    error InvalidRoot();
    error ChainAlreadyOpen(bytes32 agentId);
    error ChainNotOpen(bytes32 agentId);
    error NotChainController(bytes32 agentId, address caller);
    error RootAlreadyCurrent(bytes32 agentId, bytes32 root);

    event PolicyRootChainOpened(bytes32 indexed agentId, address indexed controller, bytes32 indexed root, uint64 version);
    event PolicyRootUpdated(
        bytes32 indexed agentId,
        address indexed controller,
        bytes32 indexed previousRoot,
        bytes32 newRoot,
        uint64 version
    );
    event ControllerTransferred(bytes32 indexed agentId, address indexed previousController, address indexed newController);

    mapping(bytes32 agentId => ChainState state) private chains;
    mapping(bytes32 agentId => mapping(uint64 version => RootRecord record)) private rootHistory;

    function openChain(bytes32 agentId, bytes32 initialRoot) external {
        if (agentId == bytes32(0)) {
            revert InvalidAgentId();
        }

        if (initialRoot == bytes32(0)) {
            revert InvalidRoot();
        }

        if (chains[agentId].controller != address(0)) {
            revert ChainAlreadyOpen(agentId);
        }

        RootRecord memory record =
            RootRecord({root: initialRoot, previousRoot: bytes32(0), version: 1, updatedAt: uint64(block.timestamp)});

        chains[agentId] = ChainState({controller: msg.sender, current: record});
        rootHistory[agentId][record.version] = record;

        emit PolicyRootChainOpened(agentId, msg.sender, initialRoot, record.version);
    }

    function updateRoot(bytes32 agentId, bytes32 newRoot) external {
        ChainState storage state = _chain(agentId);

        if (msg.sender != state.controller) {
            revert NotChainController(agentId, msg.sender);
        }

        if (newRoot == bytes32(0)) {
            revert InvalidRoot();
        }

        if (newRoot == state.current.root) {
            revert RootAlreadyCurrent(agentId, newRoot);
        }

        RootRecord memory record = RootRecord({
            root: newRoot,
            previousRoot: state.current.root,
            version: state.current.version + 1,
            updatedAt: uint64(block.timestamp)
        });

        state.current = record;
        rootHistory[agentId][record.version] = record;

        emit PolicyRootUpdated(agentId, msg.sender, record.previousRoot, newRoot, record.version);
    }

    function transferController(bytes32 agentId, address newController) external {
        ChainState storage state = _chain(agentId);

        if (msg.sender != state.controller) {
            revert NotChainController(agentId, msg.sender);
        }

        if (newController == address(0)) {
            revert InvalidController();
        }

        address previousController = state.controller;
        state.controller = newController;

        emit ControllerTransferred(agentId, previousController, newController);
    }

    function controllerOf(bytes32 agentId) external view returns (address) {
        return _chain(agentId).controller;
    }

    function currentRoot(bytes32 agentId) external view returns (bytes32) {
        return _chain(agentId).current.root;
    }

    function currentVersion(bytes32 agentId) external view returns (uint64) {
        return _chain(agentId).current.version;
    }

    function currentRecord(bytes32 agentId) external view returns (RootRecord memory) {
        return _chain(agentId).current;
    }

    function historicalRecord(bytes32 agentId, uint64 version) external view returns (RootRecord memory) {
        _chain(agentId);

        return rootHistory[agentId][version];
    }

    function isCurrentRoot(bytes32 agentId, bytes32 root) external view returns (bool) {
        ChainState storage state = chains[agentId];

        return state.controller != address(0) && state.current.root == root;
    }

    function _chain(bytes32 agentId) private view returns (ChainState storage state) {
        state = chains[agentId];

        if (state.controller == address(0)) {
            revert ChainNotOpen(agentId);
        }
    }
}
