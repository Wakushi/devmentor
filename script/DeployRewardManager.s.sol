// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {RewardManager} from "../src/RewardManager.sol";

contract DeployRewardManager is Script {
    function run() external returns (RewardManager) {
        string memory baseUri = "https://tan-key-moth-8.mypinata.cloud/ipfs/";
        address router = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
        bytes32 donId = bytes32("fun-ethereum-sepolia-1");

        vm.startBroadcast();
        RewardManager rewardManager = new RewardManager(baseUri, router, donId);
        vm.stopBroadcast();

        return (rewardManager);
    }
}
