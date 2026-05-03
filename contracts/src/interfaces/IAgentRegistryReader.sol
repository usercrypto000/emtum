// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IAgentRegistryReader {
    function ownerOf(bytes32 agentId) external view returns (address);
    function policyRootChain() external view returns (address);
}
