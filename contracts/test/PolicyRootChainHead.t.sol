// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PolicyRootChainHead} from "../src/PolicyRootChainHead.sol";

contract PolicyRootChainHeadTest is Test {
    PolicyRootChainHead internal chainHead;

    address internal agent = address(0xA11CE);
    address internal controller = address(0xB0B);
    address internal attacker = address(0xBAD);

    bytes32 internal constant ROOT_V1 = keccak256("policy.root.v1");
    bytes32 internal constant ROOT_V2 = keccak256("policy.root.v2");

    function setUp() public {
        chainHead = new PolicyRootChainHead();
    }

    function test_RegisterAgentSetsController() public {
        chainHead.registerAgent(agent, controller);
        assertEq(chainHead.getController(agent), controller);
    }

    function test_CompromisedKeyCannotOverwriteController() public {
        chainHead.registerAgent(agent, controller);

        // Attacker attempts to overwrite the registered controller
        vm.expectRevert(PolicyRootChainHead.AgentAlreadyRegistered.selector);
        chainHead.registerAgent(agent, attacker);
    }

    function test_OnlyControllerCanAdvanceRoot() public {
        chainHead.registerAgent(agent, controller);

        // Attacker tries to advance root
        vm.expectRevert(PolicyRootChainHead.NotAgentController.selector);
        vm.prank(attacker);
        chainHead.advanceRoot(agent, ROOT_V1);

        // Controller advances root successfully
        vm.prank(controller);
        chainHead.advanceRoot(agent, ROOT_V1);

        (bytes32 currentRoot, uint256 versionNonce, ) = chainHead.getRootPointer(agent);
        assertEq(currentRoot, ROOT_V1);
        assertEq(versionNonce, 1);
    }

    function test_RevokeRootSetsZeroRootAndBumpsNonce() public {
        chainHead.registerAgent(agent, controller);

        vm.prank(controller);
        chainHead.advanceRoot(agent, ROOT_V1);

        // Revoke root
        vm.prank(controller);
        chainHead.revokeRoot(agent);

        (bytes32 currentRoot, uint256 versionNonce, ) = chainHead.getRootPointer(agent);
        assertEq(currentRoot, bytes32(0));
        assertEq(versionNonce, 2);
    }

    function mockVerify(bytes32 root) public pure {
        if (root == bytes32(0)) {
            revert("Verifier encounter 0x0 root");
        }
    }

    function test_VerifierRevertsOnZeroRoot() public {
        chainHead.registerAgent(agent, controller);

        vm.prank(controller);
        chainHead.advanceRoot(agent, ROOT_V1);

        // Valid root works
        (bytes32 currentRoot, , ) = chainHead.getRootPointer(agent);
        mockVerify(currentRoot);

        // Revoke the root
        vm.prank(controller);
        chainHead.revokeRoot(agent);

        (bytes32 revokedRoot, , ) = chainHead.getRootPointer(agent);
        assertEq(revokedRoot, bytes32(0));

        // Verifying revoked root must revert
        vm.expectRevert("Verifier encounter 0x0 root");
        this.mockVerify(revokedRoot);
    }
}
