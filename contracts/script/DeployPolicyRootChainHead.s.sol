// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {PolicyRootChainHead} from "../src/PolicyRootChainHead.sol";

contract DeployPolicyRootChainHead is Script {
    function run() external returns (address chainHeadAddress) {
        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );

        vm.startBroadcast(deployerPrivateKey);

        PolicyRootChainHead chainHead = new PolicyRootChainHead();

        vm.stopBroadcast();

        console2.log("PolicyRootChainHead deployed at:", address(chainHead));

        return address(chainHead);
    }
}
