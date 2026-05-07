// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {DeploySimulation} from "../script/DeploySimulation.s.sol";

contract DeploySimulationTest is Test {
    function test_DeploymentScriptWiresSimulationSurface() public {
        DeploySimulation deployer = new DeploySimulation();
        DeploySimulation.Deployment memory deployment = deployer.run();

        assertGt(address(deployment.policyRootChain).code.length, 0);
        assertGt(address(deployment.agentRegistry).code.length, 0);
        assertGt(address(deployment.eas).code.length, 0);
        assertGt(address(deployment.attestationBoundary).code.length, 0);
        assertGt(address(deployment.honkVerifier).code.length, 0);
        assertGt(address(deployment.verifierAdapter).code.length, 0);
        assertGt(address(deployment.authorizationReader).code.length, 0);
        assertGt(address(deployment.taskAuthorizationGate).code.length, 0);
        assertGt(address(deployment.taskIntentMarket).code.length, 0);
        assertGt(address(deployment.taskFundingEscrow).code.length, 0);
        assertGt(address(deployment.taskResultRegistry).code.length, 0);
        assertGt(address(deployment.taskAcceptanceRegistry).code.length, 0);
        assertGt(address(deployment.taskLifecycleView).code.length, 0);

        assertEq(address(deployment.agentRegistry.policyRootChain()), address(deployment.policyRootChain));
        assertEq(address(deployment.attestationBoundary.agentRegistry()), address(deployment.agentRegistry));
        assertEq(address(deployment.attestationBoundary.eas()), address(deployment.eas));
        assertEq(address(deployment.verifierAdapter.verifier()), address(deployment.honkVerifier));
        assertEq(address(deployment.authorizationReader.policyRootChain()), address(deployment.policyRootChain));
        assertEq(address(deployment.authorizationReader.verifierAdapter()), address(deployment.verifierAdapter));
        assertEq(address(deployment.taskAuthorizationGate.agentRegistry()), address(deployment.agentRegistry));
        assertEq(
            address(deployment.taskAuthorizationGate.attestationBoundary()), address(deployment.attestationBoundary)
        );
        assertEq(
            address(deployment.taskAuthorizationGate.authorizationReader()), address(deployment.authorizationReader)
        );
        assertEq(address(deployment.taskIntentMarket.agentRegistry()), address(deployment.agentRegistry));
        assertEq(address(deployment.taskIntentMarket.authorizationGate()), address(deployment.taskAuthorizationGate));
        assertEq(address(deployment.taskFundingEscrow.agentRegistry()), address(deployment.agentRegistry));
        assertEq(address(deployment.taskFundingEscrow.taskIntentMarket()), address(deployment.taskIntentMarket));
        assertEq(
            address(deployment.taskFundingEscrow.taskAcceptanceRegistry()), address(deployment.taskAcceptanceRegistry)
        );
        assertEq(address(deployment.taskResultRegistry.agentRegistry()), address(deployment.agentRegistry));
        assertEq(address(deployment.taskResultRegistry.taskIntentMarket()), address(deployment.taskIntentMarket));
        assertEq(address(deployment.taskAcceptanceRegistry.taskIntentMarket()), address(deployment.taskIntentMarket));
        assertEq(
            address(deployment.taskAcceptanceRegistry.taskResultRegistry()), address(deployment.taskResultRegistry)
        );
        assertEq(address(deployment.taskLifecycleView.taskIntentMarket()), address(deployment.taskIntentMarket));
        assertEq(address(deployment.taskLifecycleView.taskFundingEscrow()), address(deployment.taskFundingEscrow));
        assertEq(address(deployment.taskLifecycleView.taskResultRegistry()), address(deployment.taskResultRegistry));
        assertEq(
            address(deployment.taskLifecycleView.taskAcceptanceRegistry()), address(deployment.taskAcceptanceRegistry)
        );
    }
}
