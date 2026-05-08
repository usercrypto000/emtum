// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {EmtunAuthorizationStatusView} from "../EmtunAuthorizationStatusView.sol";

interface IEmtunAuthorizationStatusReader {
    function getAgentAuthorizationStatus(bytes32 agentId, bytes calldata proof, bytes32 actionHash)
        external
        view
        returns (EmtunAuthorizationStatusView.AgentAuthorizationStatus memory status);
}
