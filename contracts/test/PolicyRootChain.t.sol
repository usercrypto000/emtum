// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PolicyRootChain} from "../src/PolicyRootChain.sol";

contract PolicyRootChainTest is Test {
    PolicyRootChain internal chain;

    bytes32 internal constant AGENT_ID = keccak256("emtun.agent.alpha");
    bytes32 internal constant ROOT_V1 = keccak256("policy.root.v1");
    bytes32 internal constant ROOT_V2 = keccak256("policy.root.v2");
    bytes32 internal constant ROOT_V3 = keccak256("policy.root.v3");

    address internal controller = address(0xA11CE);
    address internal nextController = address(0xB0B);
    address internal attacker = address(0xBAD);

    function setUp() public {
        chain = new PolicyRootChain();
    }

    function test_OpenChainSetsControllerAndInitialRoot() public {
        vm.prank(controller);
        chain.openChain(AGENT_ID, ROOT_V1);

        PolicyRootChain.RootRecord memory record = chain.currentRecord(AGENT_ID);

        assertEq(chain.controllerOf(AGENT_ID), controller);
        assertEq(record.root, ROOT_V1);
        assertEq(record.previousRoot, bytes32(0));
        assertEq(record.version, 1);
        assertTrue(chain.isCurrentRoot(AGENT_ID, ROOT_V1));
    }

    function test_UpdateRootAdvancesChainHeadOnly() public {
        vm.startPrank(controller);
        chain.openChain(AGENT_ID, ROOT_V1);
        chain.updateRoot(AGENT_ID, ROOT_V2);
        vm.stopPrank();

        PolicyRootChain.RootRecord memory current = chain.currentRecord(AGENT_ID);
        PolicyRootChain.RootRecord memory historical = chain.historicalRecord(AGENT_ID, 1);

        assertEq(current.root, ROOT_V2);
        assertEq(current.previousRoot, ROOT_V1);
        assertEq(current.version, 2);
        assertEq(historical.root, ROOT_V1);
        assertFalse(chain.isCurrentRoot(AGENT_ID, ROOT_V1));
        assertTrue(chain.isCurrentRoot(AGENT_ID, ROOT_V2));
    }

    function test_UpdateRootKeepsFullHistoryWithoutVersionWindow() public {
        vm.startPrank(controller);
        chain.openChain(AGENT_ID, ROOT_V1);
        chain.updateRoot(AGENT_ID, ROOT_V2);
        chain.updateRoot(AGENT_ID, ROOT_V3);
        vm.stopPrank();

        assertEq(chain.currentVersion(AGENT_ID), 3);
        assertEq(chain.historicalRecord(AGENT_ID, 1).root, ROOT_V1);
        assertEq(chain.historicalRecord(AGENT_ID, 2).root, ROOT_V2);
        assertEq(chain.historicalRecord(AGENT_ID, 3).root, ROOT_V3);
        assertFalse(chain.isCurrentRoot(AGENT_ID, ROOT_V1));
        assertFalse(chain.isCurrentRoot(AGENT_ID, ROOT_V2));
        assertTrue(chain.isCurrentRoot(AGENT_ID, ROOT_V3));
    }

    function test_OnlyControllerCanUpdateRoot() public {
        vm.prank(controller);
        chain.openChain(AGENT_ID, ROOT_V1);

        vm.expectRevert(abi.encodeWithSelector(PolicyRootChain.NotChainController.selector, AGENT_ID, attacker));
        vm.prank(attacker);
        chain.updateRoot(AGENT_ID, ROOT_V2);
    }

    function test_ControllerCanTransferControl() public {
        vm.startPrank(controller);
        chain.openChain(AGENT_ID, ROOT_V1);
        chain.transferController(AGENT_ID, nextController);
        vm.stopPrank();

        assertEq(chain.controllerOf(AGENT_ID), nextController);

        vm.prank(nextController);
        chain.updateRoot(AGENT_ID, ROOT_V2);

        assertTrue(chain.isCurrentRoot(AGENT_ID, ROOT_V2));
    }

    function test_PreviousControllerCannotUpdateAfterTransfer() public {
        vm.startPrank(controller);
        chain.openChain(AGENT_ID, ROOT_V1);
        chain.transferController(AGENT_ID, nextController);
        vm.expectRevert(abi.encodeWithSelector(PolicyRootChain.NotChainController.selector, AGENT_ID, controller));
        chain.updateRoot(AGENT_ID, ROOT_V2);
        vm.stopPrank();
    }

    function test_RevertsOnZeroRoot() public {
        vm.expectRevert(PolicyRootChain.InvalidRoot.selector);
        chain.openChain(AGENT_ID, bytes32(0));
    }

    function test_RevertsOnZeroAgentId() public {
        vm.expectRevert(PolicyRootChain.InvalidAgentId.selector);
        chain.openChain(bytes32(0), ROOT_V1);
    }

    function test_UnopenedChainDoesNotAcceptCurrentRoot() public view {
        assertFalse(chain.isCurrentRoot(AGENT_ID, ROOT_V1));
    }

    function test_CurrentRootRevertsForUnopenedChain() public {
        vm.expectRevert(abi.encodeWithSelector(PolicyRootChain.ChainNotOpen.selector, AGENT_ID));
        chain.currentRoot(AGENT_ID);
    }

    function test_RevertsOnDuplicateCurrentRoot() public {
        vm.startPrank(controller);
        chain.openChain(AGENT_ID, ROOT_V1);
        vm.expectRevert(abi.encodeWithSelector(PolicyRootChain.RootAlreadyCurrent.selector, AGENT_ID, ROOT_V1));
        chain.updateRoot(AGENT_ID, ROOT_V1);
        vm.stopPrank();
    }

    function test_RevertsWhenOpeningSameChainTwice() public {
        vm.startPrank(controller);
        chain.openChain(AGENT_ID, ROOT_V1);
        vm.expectRevert(abi.encodeWithSelector(PolicyRootChain.ChainAlreadyOpen.selector, AGENT_ID));
        chain.openChain(AGENT_ID, ROOT_V2);
        vm.stopPrank();
    }
}
