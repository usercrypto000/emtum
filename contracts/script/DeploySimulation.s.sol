// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {EmtunAuthorizationReader} from "../src/EmtunAuthorizationReader.sol";
import {EmtunEASAttestationBoundary} from "../src/EmtunEASAttestationBoundary.sol";
import {EmtunVerifierAdapter} from "../src/EmtunVerifierAdapter.sol";
import {MockEAS} from "../src/MockEAS.sol";
import {PolicyRootChain} from "../src/PolicyRootChain.sol";
import {TaskAuthorizationGate} from "../src/TaskAuthorizationGate.sol";
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

        vm.stopBroadcast();
    }
}
