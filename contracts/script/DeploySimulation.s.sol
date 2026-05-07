// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {EmtunAuthorizationReader} from "../src/EmtunAuthorizationReader.sol";
import {EmtunEASAttestationBoundary} from "../src/EmtunEASAttestationBoundary.sol";
import {EmtunVerifierAdapter} from "../src/EmtunVerifierAdapter.sol";
import {MockEAS} from "../src/MockEAS.sol";
import {PolicyRootChain} from "../src/PolicyRootChain.sol";
import {TaskAcceptanceRegistry} from "../src/TaskAcceptanceRegistry.sol";
import {TaskAuthorizationGate} from "../src/TaskAuthorizationGate.sol";
import {TaskFundingEscrow} from "../src/TaskFundingEscrow.sol";
import {TaskIntentMarket} from "../src/TaskIntentMarket.sol";
import {TaskResultRegistry} from "../src/TaskResultRegistry.sol";
import {HonkVerifier} from "../src/verifiers/EmtunPolicyVerifier.sol";

contract DeploySimulation is Script {
    struct Deployment {
        PolicyRootChain policyRootChain;
        AgentRegistry agentRegistry;
        MockEAS eas;
        EmtunEASAttestationBoundary attestationBoundary;
        HonkVerifier honkVerifier;
        EmtunVerifierAdapter verifierAdapter;
        EmtunAuthorizationReader authorizationReader;
        TaskAuthorizationGate taskAuthorizationGate;
        TaskIntentMarket taskIntentMarket;
        TaskFundingEscrow taskFundingEscrow;
        TaskResultRegistry taskResultRegistry;
        TaskAcceptanceRegistry taskAcceptanceRegistry;
    }

    function run() external returns (Deployment memory deployment) {
        vm.startBroadcast();

        deployment.policyRootChain = new PolicyRootChain();
        deployment.agentRegistry = new AgentRegistry(address(deployment.policyRootChain));
        deployment.eas = new MockEAS();
        deployment.attestationBoundary =
            new EmtunEASAttestationBoundary(address(deployment.agentRegistry), address(deployment.eas));
        deployment.honkVerifier = new HonkVerifier();
        deployment.verifierAdapter = new EmtunVerifierAdapter(address(deployment.honkVerifier));
        deployment.authorizationReader =
            new EmtunAuthorizationReader(address(deployment.policyRootChain), address(deployment.verifierAdapter));
        deployment.taskAuthorizationGate = new TaskAuthorizationGate(
            address(deployment.agentRegistry),
            address(deployment.attestationBoundary),
            address(deployment.authorizationReader)
        );
        deployment.taskIntentMarket =
            new TaskIntentMarket(address(deployment.agentRegistry), address(deployment.taskAuthorizationGate));
        deployment.taskFundingEscrow = new TaskFundingEscrow(address(deployment.taskIntentMarket));
        deployment.taskResultRegistry =
            new TaskResultRegistry(address(deployment.agentRegistry), address(deployment.taskIntentMarket));
        deployment.taskAcceptanceRegistry =
            new TaskAcceptanceRegistry(address(deployment.taskIntentMarket), address(deployment.taskResultRegistry));

        vm.stopBroadcast();
    }
}
