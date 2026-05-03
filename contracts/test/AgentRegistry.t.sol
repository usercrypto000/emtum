// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {PolicyRootChain} from "../src/PolicyRootChain.sol";

contract AgentRegistryTest is Test {
    AgentRegistry internal registry;
    PolicyRootChain internal rootChain;

    bytes32 internal constant AGENT_ID = keccak256("emtun.agent.alpha");
    bytes32 internal constant INITIAL_ROOT = keccak256("policy.root.initial");
    bytes32 internal constant NEXT_ROOT = keccak256("policy.root.next");

    address internal owner = address(0xA11CE);
    address internal nextOwner = address(0xB0B);
    address internal attacker = address(0xBAD);

    function setUp() public {
        rootChain = new PolicyRootChain();
        registry = new AgentRegistry(address(rootChain));
    }

    function test_RegisterAgentCreatesIdentityAndPolicyChain() public {
        vm.prank(owner);
        registry.registerAgent(AGENT_ID, INITIAL_ROOT);

        assertTrue(registry.isRegistered(AGENT_ID));
        assertEq(registry.ownerOf(AGENT_ID), owner);
        assertEq(registry.currentPolicyRoot(AGENT_ID), INITIAL_ROOT);
        assertEq(registry.policyControllerOf(AGENT_ID), owner);
        assertTrue(rootChain.isCurrentRoot(AGENT_ID, INITIAL_ROOT));
    }

    function test_RegisteredPolicyControllerCanRotateRoot() public {
        vm.startPrank(owner);
        registry.registerAgent(AGENT_ID, INITIAL_ROOT);
        rootChain.updateRoot(AGENT_ID, NEXT_ROOT);
        vm.stopPrank();

        assertEq(registry.currentPolicyRoot(AGENT_ID), NEXT_ROOT);
        assertFalse(rootChain.isCurrentRoot(AGENT_ID, INITIAL_ROOT));
        assertTrue(rootChain.isCurrentRoot(AGENT_ID, NEXT_ROOT));
    }

    function test_TransferAgentOwnerDoesNotTransferPolicyController() public {
        vm.startPrank(owner);
        registry.registerAgent(AGENT_ID, INITIAL_ROOT);
        registry.transferAgentOwner(AGENT_ID, nextOwner);
        vm.stopPrank();

        assertEq(registry.ownerOf(AGENT_ID), nextOwner);
        assertEq(registry.policyControllerOf(AGENT_ID), owner);
    }

    function test_OnlyAgentOwnerCanTransferOwner() public {
        vm.prank(owner);
        registry.registerAgent(AGENT_ID, INITIAL_ROOT);

        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.NotAgentOwner.selector, AGENT_ID, attacker));
        vm.prank(attacker);
        registry.transferAgentOwner(AGENT_ID, nextOwner);
    }

    function test_RevertsOnDuplicateRegistration() public {
        vm.startPrank(owner);
        registry.registerAgent(AGENT_ID, INITIAL_ROOT);
        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.AgentAlreadyRegistered.selector, AGENT_ID));
        registry.registerAgent(AGENT_ID, NEXT_ROOT);
        vm.stopPrank();
    }

    function test_RevertsOnZeroAgentId() public {
        vm.expectRevert(AgentRegistry.InvalidAgentId.selector);
        registry.registerAgent(bytes32(0), INITIAL_ROOT);
    }

    function test_RevertsOnZeroRoot() public {
        vm.expectRevert(AgentRegistry.InvalidRoot.selector);
        registry.registerAgent(AGENT_ID, bytes32(0));
    }

    function test_RevertsOnZeroNewOwner() public {
        vm.startPrank(owner);
        registry.registerAgent(AGENT_ID, INITIAL_ROOT);
        vm.expectRevert(AgentRegistry.InvalidOwner.selector);
        registry.transferAgentOwner(AGENT_ID, address(0));
        vm.stopPrank();
    }

    function test_RevertsWhenReadingUnregisteredAgent() public {
        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.AgentNotRegistered.selector, AGENT_ID));
        registry.ownerOf(AGENT_ID);
    }

    function test_RevertsWhenRootChainIsNotContract() public {
        vm.expectRevert(AgentRegistry.InvalidPolicyRootChain.selector);
        new AgentRegistry(address(0));
    }
}
