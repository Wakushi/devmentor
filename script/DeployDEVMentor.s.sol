// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DEVMentor} from "../src/DEVMentor.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Interaction.s.sol";

contract DeployDEVMentor is Script {
    function run() external returns (DEVMentor, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (
            address vrfCoordinator,
            bytes32 gasLane,
            uint64 subscriptionId,
            uint32 callbackGasLimit,
            address link,
            uint256 deployerKey,
            address priceFeed,
            ,

        ) = helperConfig.activeNetworkConfig();

        if (subscriptionId == 0) {
            CreateSubscription createSubscription = new CreateSubscription();
            subscriptionId = createSubscription.createSubscription(
                vrfCoordinator,
                deployerKey
            );
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(
                vrfCoordinator,
                subscriptionId,
                link,
                deployerKey
            );
        }

        string[] memory languages = new string[](10);
        languages[0] = "English";
        languages[1] = "Spanish";
        languages[2] = "French";
        languages[3] = "German";
        languages[4] = "Italian";
        languages[5] = "Japanese";
        languages[6] = "Korean";
        languages[7] = "Portuguese";
        languages[8] = "Russian";
        languages[9] = "Chinese";

        DEVMentor.DEVMentorConfig memory config = DEVMentor.DEVMentorConfig({
            vrfCoordinator: vrfCoordinator,
            priceFeed: priceFeed,
            gasLane: gasLane,
            subscriptionId: subscriptionId,
            callbackGasLimit: callbackGasLimit,
            languages: languages
        });

        vm.startBroadcast();
        DEVMentor devMentor = new DEVMentor(config);
        vm.stopBroadcast();

        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(
            address(devMentor),
            vrfCoordinator,
            subscriptionId,
            deployerKey
        );
        return (devMentor, helperConfig);
    }
}
