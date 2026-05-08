// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {TaskLifecycleView} from "../TaskLifecycleView.sol";

interface ITaskLifecycleReader {
    function getTaskLifecycle(uint256 taskId) external view returns (TaskLifecycleView.TaskLifecycle memory lifecycle);
}
