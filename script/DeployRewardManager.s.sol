// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {RewardManager} from "../src/RewardManager.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployRewardManager is Script {
    function run() external returns (RewardManager) {
        string memory baseUri = "https://tan-key-moth-8.mypinata.cloud/ipfs/";

        HelperConfig helperConfig = new HelperConfig();
        (, , , , , , , address router, bytes32 donId) = helperConfig
            .activeNetworkConfig();

        vm.startBroadcast();
        RewardManager rewardManager = new RewardManager(baseUri, router, donId);
        vm.stopBroadcast();

        return (rewardManager);
    }
}
