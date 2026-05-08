// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {DeploySimulation} from "../script/DeploySimulation.s.sol";
import {IEmtunAuthorizationStatusReader} from "../src/interfaces/IEmtunAuthorizationStatusReader.sol";
import {ITaskLifecycleReader} from "../src/interfaces/ITaskLifecycleReader.sol";

contract SdkReadInterfacesTest is Test {
    function test_ReadInterfacesMatchDeployedViewSelectors() public {
        DeploySimulation deployer = new DeploySimulation();
        DeploySimulation.Deployment memory deployment = deployer.run();

        IEmtunAuthorizationStatusReader authorizationStatusReader =
            IEmtunAuthorizationStatusReader(address(deployment.authorizationStatusView));
        ITaskLifecycleReader taskLifecycleReader = ITaskLifecycleReader(address(deployment.taskLifecycleView));

        assertEq(
            IEmtunAuthorizationStatusReader.getAgentAuthorizationStatus.selector,
            bytes4(keccak256("getAgentAuthorizationStatus(bytes32,bytes,bytes32)"))
        );
        assertEq(ITaskLifecycleReader.getTaskLifecycle.selector, bytes4(keccak256("getTaskLifecycle(uint256)")));

        assertFalse(
            authorizationStatusReader.getAgentAuthorizationStatus(
                keccak256("unknown.agent"), "", keccak256("unknown.action")
            )
            .registered
        );
        assertEq(uint8(taskLifecycleReader.getTaskLifecycle(1).taskStatus), 0);
    }
}
