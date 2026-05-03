// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPolicyRootReader {
    function currentRoot(bytes32 agentId) external view returns (bytes32);
}
