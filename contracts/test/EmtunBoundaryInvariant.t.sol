// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {EmtunEASAttestationBoundary} from "../src/EmtunEASAttestationBoundary.sol";
import {MockEAS} from "../src/MockEAS.sol";
import {PolicyRootChain} from "../src/PolicyRootChain.sol";

contract EmtunBoundaryHandler is Test {
    struct AgentModel {
        bool registered;
        address owner;
        bytes32 activeUid;
        bytes32 revokedUid;
        address attestedOwner;
    }

    AgentRegistry public immutable registry;
    EmtunEASAttestationBoundary public immutable boundary;
    MockEAS public immutable eas;
    PolicyRootChain public immutable rootChain;

    bytes32[3] public agentIds;

    mapping(bytes32 agentId => AgentModel model) internal models;
    uint256 internal nextRootNonce = 1;

    constructor(
        AgentRegistry registry_,
        EmtunEASAttestationBoundary boundary_,
        MockEAS eas_,
        PolicyRootChain rootChain_
    ) {
        registry = registry_;
        boundary = boundary_;
        eas = eas_;
        rootChain = rootChain_;
        agentIds[0] = keccak256("emtun.boundary.alpha");
        agentIds[1] = keccak256("emtun.boundary.beta");
        agentIds[2] = keccak256("emtun.boundary.gamma");
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

    function transferOwner(uint8 agentSeed, uint8 actorSeed, uint8 newOwnerSeed) external {
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
    }

    function attestAgent(uint8 agentSeed, uint8 actorSeed) external {
        bytes32 agentId = _agentId(agentSeed);
        AgentModel storage model = models[agentId];
        address actor = _actor(actorSeed);

        vm.prank(actor);

        if (!model.registered) {
            vm.expectRevert(abi.encodeWithSelector(AgentRegistry.AgentNotRegistered.selector, agentId));
            boundary.attestAgent(agentId);
            return;
        }

        if (actor != model.owner) {
            vm.expectRevert(abi.encodeWithSelector(EmtunEASAttestationBoundary.NotAgentOwner.selector, agentId, actor));
            boundary.attestAgent(agentId);
            return;
        }

        if (
            model.activeUid != bytes32(0) && eas.isAttestationActive(model.activeUid)
                && model.attestedOwner == model.owner
        ) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    EmtunEASAttestationBoundary.AttestationAlreadyActive.selector, agentId, model.activeUid
                )
            );
            boundary.attestAgent(agentId);
            return;
        }

        bytes32 uid = boundary.attestAgent(agentId);

        model.activeUid = uid;
        model.attestedOwner = actor;
        assertTrue(eas.isAttestationActive(uid));
        assertTrue(boundary.hasActiveAgentAttestation(agentId));
        assertEq(boundary.activeAttestationUid(agentId), uid);
        assertEq(boundary.attestedOwner(agentId), actor);
    }

    function revokeAgentAttestation(uint8 agentSeed, uint8 actorSeed) external {
        bytes32 agentId = _agentId(agentSeed);
        AgentModel storage model = models[agentId];
        address actor = _actor(actorSeed);

        vm.prank(actor);

        if (model.activeUid == bytes32(0) || !eas.isAttestationActive(model.activeUid)) {
            vm.expectRevert(abi.encodeWithSelector(EmtunEASAttestationBoundary.NoActiveAttestation.selector, agentId));
            boundary.revokeAgentAttestation(agentId);
            return;
        }

        if (actor != model.owner) {
            vm.expectRevert(abi.encodeWithSelector(EmtunEASAttestationBoundary.NotAgentOwner.selector, agentId, actor));
            boundary.revokeAgentAttestation(agentId);
            return;
        }

        bytes32 uidToRevoke = model.activeUid;

        boundary.revokeAgentAttestation(agentId);

        model.activeUid = bytes32(0);
        model.revokedUid = uidToRevoke;
        model.attestedOwner = address(0);

        assertFalse(eas.isAttestationActive(uidToRevoke));
        assertFalse(boundary.hasActiveAgentAttestation(agentId));
        assertEq(boundary.activeAttestationUid(agentId), bytes32(0));
        assertEq(boundary.attestedOwner(agentId), address(0));
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

    function activeUid(bytes32 agentId) external view returns (bytes32) {
        return models[agentId].activeUid;
    }

    function expectedAttestedOwner(bytes32 agentId) external view returns (address) {
        return models[agentId].attestedOwner;
    }

    function revokedUid(bytes32 agentId) external view returns (bytes32) {
        return models[agentId].revokedUid;
    }

    function _agentId(uint8 seed) internal view returns (bytes32) {
        return agentIds[uint256(seed) % agentIds.length];
    }

    function _actor(uint8 seed) internal pure returns (address) {
        return address(uint160(uint256(seed) + 1));
    }

    function _nextRoot(bytes32 agentId) internal returns (bytes32 root) {
        root = keccak256(abi.encode("boundary.policy.root", agentId, nextRootNonce));
        nextRootNonce += 1;
    }
}

contract EmtunBoundaryInvariantTest is Test {
    AgentRegistry internal registry;
    EmtunEASAttestationBoundary internal boundary;
    EmtunBoundaryHandler internal handler;
    MockEAS internal eas;
    PolicyRootChain internal rootChain;

    function setUp() public {
        rootChain = new PolicyRootChain();
        registry = new AgentRegistry(address(rootChain));
        eas = new MockEAS();
        boundary = new EmtunEASAttestationBoundary(address(registry), address(eas));
        handler = new EmtunBoundaryHandler(registry, boundary, eas, rootChain);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = EmtunBoundaryHandler.registerAgent.selector;
        selectors[1] = EmtunBoundaryHandler.transferOwner.selector;
        selectors[2] = EmtunBoundaryHandler.attestAgent.selector;
        selectors[3] = EmtunBoundaryHandler.revokeAgentAttestation.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_ActiveBoundaryStateMatchesEASLiveness() public view {
        uint256 count = handler.agentCount();

        for (uint256 i = 0; i < count; i++) {
            bytes32 agentId = handler.agentIds(i);
            bytes32 uid = handler.activeUid(agentId);
            address attestedOwner = handler.expectedAttestedOwner(agentId);
            address currentOwner = handler.isRegistered(agentId) ? registry.ownerOf(agentId) : address(0);

            assertEq(boundary.activeAttestationUid(agentId), uid);
            assertEq(boundary.attestedOwner(agentId), attestedOwner);
            assertEq(
                boundary.hasActiveAgentAttestation(agentId),
                uid != bytes32(0) && eas.isAttestationActive(uid) && attestedOwner == currentOwner
            );
        }
    }

    function invariant_RevokedAttestationsAreInactive() public view {
        uint256 count = handler.agentCount();

        for (uint256 i = 0; i < count; i++) {
            bytes32 agentId = handler.agentIds(i);
            bytes32 uid = handler.revokedUid(agentId);

            if (uid == bytes32(0)) {
                continue;
            }

            assertFalse(eas.isAttestationActive(uid));
            assertFalse(boundary.activeAttestationUid(agentId) == uid);
        }
    }

    function invariant_ActiveAttestationsEncodeRegisteredAgentBoundary() public view {
        uint256 count = handler.agentCount();

        for (uint256 i = 0; i < count; i++) {
            bytes32 agentId = handler.agentIds(i);
            bytes32 uid = handler.activeUid(agentId);

            if (uid == bytes32(0)) {
                continue;
            }

            MockEAS.Attestation memory attestation = eas.getAttestation(uid);
            (bytes32 attestedAgentId, address attestedRegistry, address attestedRootChain) =
                abi.decode(attestation.data, (bytes32, address, address));
            address attestedOwner = handler.expectedAttestedOwner(agentId);

            assertTrue(handler.isRegistered(agentId));
            assertEq(registry.ownerOf(agentId), handler.expectedOwner(agentId));
            assertEq(boundary.attestedOwner(agentId), attestedOwner);
            assertEq(attestation.recipient, attestedOwner);
            assertEq(attestation.schema, boundary.AGENT_IDENTITY_SCHEMA());
            assertEq(attestation.attester, address(boundary));
            assertEq(attestedAgentId, agentId);
            assertEq(attestedRegistry, address(registry));
            assertEq(attestedRootChain, address(rootChain));
        }
    }
}
