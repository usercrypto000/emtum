// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {PolicyRootChain} from "../src/PolicyRootChain.sol";

contract PolicyRootChainHandler is Test {
    struct ChainModel {
        bool open;
        address controller;
        bytes32 currentRoot;
        bytes32 previousRoot;
        uint64 version;
    }

    PolicyRootChain public immutable chain;

    bytes32[3] public agentIds;

    mapping(bytes32 agentId => ChainModel model) internal models;
    mapping(bytes32 agentId => mapping(uint64 version => bytes32 root)) internal historicalRoots;

    uint256 internal nextRootNonce = 1;

    constructor(PolicyRootChain chain_) {
        chain = chain_;
        agentIds[0] = keccak256("emtun.agent.alpha");
        agentIds[1] = keccak256("emtun.agent.beta");
        agentIds[2] = keccak256("emtun.agent.gamma");
    }

    function openChain(uint8 agentSeed, uint8 actorSeed) external {
        bytes32 agentId = _agentId(agentSeed);
        ChainModel storage model = models[agentId];
        address actor = _actor(actorSeed);
        bytes32 root = _nextRoot(agentId);

        vm.prank(actor);

        if (model.open) {
            vm.expectRevert(abi.encodeWithSelector(PolicyRootChain.ChainAlreadyOpen.selector, agentId));
            chain.openChain(agentId, root);
            return;
        }

        chain.openChain(agentId, root);

        model.open = true;
        model.controller = actor;
        model.currentRoot = root;
        model.previousRoot = bytes32(0);
        model.version = 1;
        historicalRoots[agentId][1] = root;
    }

    function updateRoot(uint8 agentSeed, uint8 actorSeed) external {
        bytes32 agentId = _agentId(agentSeed);
        ChainModel storage model = models[agentId];
        address actor = _actor(actorSeed);
        bytes32 root = _nextRoot(agentId);

        vm.prank(actor);

        if (!model.open) {
            vm.expectRevert(abi.encodeWithSelector(PolicyRootChain.ChainNotOpen.selector, agentId));
            chain.updateRoot(agentId, root);
            return;
        }

        if (actor != model.controller) {
            vm.expectRevert(abi.encodeWithSelector(PolicyRootChain.NotChainController.selector, agentId, actor));
            chain.updateRoot(agentId, root);
            return;
        }

        bytes32 previousRoot = model.currentRoot;

        chain.updateRoot(agentId, root);

        model.previousRoot = previousRoot;
        model.currentRoot = root;
        model.version += 1;
        historicalRoots[agentId][model.version] = root;
    }

    function transferController(uint8 agentSeed, uint8 actorSeed, uint8 newControllerSeed) external {
        bytes32 agentId = _agentId(agentSeed);
        ChainModel storage model = models[agentId];
        address actor = _actor(actorSeed);
        address newController = _actor(newControllerSeed);

        vm.prank(actor);

        if (!model.open) {
            vm.expectRevert(abi.encodeWithSelector(PolicyRootChain.ChainNotOpen.selector, agentId));
            chain.transferController(agentId, newController);
            return;
        }

        if (actor != model.controller) {
            vm.expectRevert(abi.encodeWithSelector(PolicyRootChain.NotChainController.selector, agentId, actor));
            chain.transferController(agentId, newController);
            return;
        }

        chain.transferController(agentId, newController);

        model.controller = newController;
    }

    function agentCount() external pure returns (uint256) {
        return 3;
    }

    function isOpen(bytes32 agentId) external view returns (bool) {
        return models[agentId].open;
    }

    function expectedController(bytes32 agentId) external view returns (address) {
        return models[agentId].controller;
    }

    function expectedCurrentRoot(bytes32 agentId) external view returns (bytes32) {
        return models[agentId].currentRoot;
    }

    function expectedPreviousRoot(bytes32 agentId) external view returns (bytes32) {
        return models[agentId].previousRoot;
    }

    function expectedVersion(bytes32 agentId) external view returns (uint64) {
        return models[agentId].version;
    }

    function expectedHistoricalRoot(bytes32 agentId, uint64 version) external view returns (bytes32) {
        return historicalRoots[agentId][version];
    }

    function _agentId(uint8 seed) internal view returns (bytes32) {
        return agentIds[uint256(seed) % agentIds.length];
    }

    function _actor(uint8 seed) internal pure returns (address) {
        return address(uint160(uint256(seed) + 1));
    }

    function _nextRoot(bytes32 agentId) internal returns (bytes32 root) {
        root = keccak256(abi.encode("policy.root", agentId, nextRootNonce));
        nextRootNonce += 1;
    }
}

contract AgentRegistryOwnershipHandler is Test {
    struct AgentModel {
        bool registered;
        address owner;
        uint64 transferCount;
    }

    AgentRegistry public immutable registry;
    PolicyRootChain public immutable rootChain;

    bytes32[3] public agentIds;

    mapping(bytes32 agentId => AgentModel model) internal models;
    uint256 internal nextRootNonce = 1;

    constructor(AgentRegistry registry_, PolicyRootChain rootChain_) {
        registry = registry_;
        rootChain = rootChain_;
        agentIds[0] = keccak256("emtun.registry.alpha");
        agentIds[1] = keccak256("emtun.registry.beta");
        agentIds[2] = keccak256("emtun.registry.gamma");
    }

    function registerAgent(uint8 agentSeed, uint8 actorSeed) external {
        bytes32 agentId = _agentId(agentSeed);
        AgentModel storage model = models[agentId];
        address actor = _actor(actorSeed);
        bytes32 root = _nextRoot(agentId);

        vm.prank(actor);

        if (model.registered) {
            vm.expectRevert(abi.encodeWithSelector(AgentRegistry.AgentAlreadyRegistered.selector, agentId));
            registry.registerAgent(agentId, root);
            return;
        }

        registry.registerAgent(agentId, root);

        model.registered = true;
        model.owner = actor;
    }

    function transferAgentOwner(uint8 agentSeed, uint8 actorSeed, uint8 newOwnerSeed) external {
        bytes32 agentId = _agentId(agentSeed);
        AgentModel storage model = models[agentId];
        address actor = _actor(actorSeed);
        address newOwner = _actor(newOwnerSeed);

        vm.prank(actor);

        if (!model.registered) {
            vm.expectRevert(abi.encodeWithSelector(AgentRegistry.AgentNotRegistered.selector, agentId));
            registry.transferAgentOwner(agentId, newOwner);
            return;
        }

        if (actor != model.owner) {
            vm.expectRevert(abi.encodeWithSelector(AgentRegistry.NotAgentOwner.selector, agentId, actor));
            registry.transferAgentOwner(agentId, newOwner);
            return;
        }

        registry.transferAgentOwner(agentId, newOwner);

        model.owner = newOwner;
        model.transferCount += 1;
    }

    function agentCount() external pure returns (uint256) {
        return 3;
    }

    function isRegistered(bytes32 agentId) external view returns (bool) {
        return models[agentId].registered;
    }

    function expectedOwner(bytes32 agentId) external view returns (address) {
        return models[agentId].owner;
    }

    function transferCount(bytes32 agentId) external view returns (uint64) {
        return models[agentId].transferCount;
    }

    function _agentId(uint8 seed) internal view returns (bytes32) {
        return agentIds[uint256(seed) % agentIds.length];
    }

    function _actor(uint8 seed) internal pure returns (address) {
        return address(uint160(uint256(seed) + 1));
    }

    function _nextRoot(bytes32 agentId) internal returns (bytes32 root) {
        root = keccak256(abi.encode("registry.policy.root", agentId, nextRootNonce));
        nextRootNonce += 1;
    }
}

contract PolicyRootChainInvariantTest is Test {
    PolicyRootChain internal chain;
    PolicyRootChainHandler internal handler;

    function setUp() public {
        chain = new PolicyRootChain();
        handler = new PolicyRootChainHandler(chain);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = PolicyRootChainHandler.openChain.selector;
        selectors[1] = PolicyRootChainHandler.updateRoot.selector;
        selectors[2] = PolicyRootChainHandler.transferController.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_CurrentRootMatchesModeledChainHead() public view {
        uint256 count = handler.agentCount();

        for (uint256 i = 0; i < count; i++) {
            bytes32 agentId = handler.agentIds(i);

            if (!handler.isOpen(agentId)) {
                assertFalse(chain.isCurrentRoot(agentId, handler.expectedCurrentRoot(agentId)));
                continue;
            }

            bytes32 expectedRoot = handler.expectedCurrentRoot(agentId);
            uint64 expectedVersion = handler.expectedVersion(agentId);
            PolicyRootChain.RootRecord memory current = chain.currentRecord(agentId);

            assertEq(chain.controllerOf(agentId), handler.expectedController(agentId));
            assertEq(chain.currentRoot(agentId), expectedRoot);
            assertEq(chain.currentVersion(agentId), expectedVersion);
            assertEq(current.root, expectedRoot);
            assertEq(current.previousRoot, handler.expectedPreviousRoot(agentId));
            assertEq(current.version, expectedVersion);
            assertTrue(chain.isCurrentRoot(agentId, expectedRoot));
        }
    }

    function invariant_HistoricalRootsBeforeHeadAreNotCurrent() public view {
        uint256 count = handler.agentCount();

        for (uint256 i = 0; i < count; i++) {
            bytes32 agentId = handler.agentIds(i);

            if (!handler.isOpen(agentId)) {
                continue;
            }

            uint64 currentVersion = handler.expectedVersion(agentId);

            for (uint64 version = 1; version < currentVersion; version++) {
                bytes32 historicalRoot = handler.expectedHistoricalRoot(agentId, version);

                assertEq(chain.historicalRecord(agentId, version).root, historicalRoot);
                assertFalse(chain.isCurrentRoot(agentId, historicalRoot));
            }
        }
    }
}

contract AgentRegistryOwnershipInvariantTest is Test {
    AgentRegistry internal registry;
    AgentRegistryOwnershipHandler internal handler;
    PolicyRootChain internal rootChain;

    function setUp() public {
        rootChain = new PolicyRootChain();
        registry = new AgentRegistry(address(rootChain));
        handler = new AgentRegistryOwnershipHandler(registry, rootChain);

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = AgentRegistryOwnershipHandler.registerAgent.selector;
        selectors[1] = AgentRegistryOwnershipHandler.transferAgentOwner.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_RegistryOwnerMatchesOnlySuccessfulOwnerTransfers() public view {
        uint256 count = handler.agentCount();

        for (uint256 i = 0; i < count; i++) {
            bytes32 agentId = handler.agentIds(i);

            if (!handler.isRegistered(agentId)) {
                assertFalse(registry.isRegistered(agentId));
                continue;
            }

            assertTrue(registry.isRegistered(agentId));
            assertEq(registry.ownerOf(agentId), handler.expectedOwner(agentId));
        }
    }

    function invariant_AgentOwnerTransferDoesNotMovePolicyController() public view {
        uint256 count = handler.agentCount();

        for (uint256 i = 0; i < count; i++) {
            bytes32 agentId = handler.agentIds(i);

            if (!handler.isRegistered(agentId) || handler.transferCount(agentId) == 0) {
                continue;
            }

            assertTrue(registry.policyControllerOf(agentId) != address(0));
            assertEq(registry.policyControllerOf(agentId), rootChain.controllerOf(agentId));
        }
    }
}
