// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Interactions.s.sol";

contract RaffleScript is Script {
    function run() external {}

    function deploy() external returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        if (config.subscriptionId == 0) {
            CreateSubscription subscription = new CreateSubscription();
            (config.subscriptionId, config.vrfCoordinator) =
                subscription.createSubscription(config.vrfCoordinator, config.account);

            FundSubscription fund = new FundSubscription();
            fund.fundSubscription(config.vrfCoordinator, config.subscriptionId, config.linkToken, config.account);
        }

        vm.startBroadcast(config.account);

        Raffle raffle = new Raffle(
            config.entryFee,
            config.interval,
            config.vrfCoordinator,
            config.gasLane,
            config.subscriptionId,
            config.callbackGasLimit
        );

        vm.stopBroadcast();

        AddConsumer consumer = new AddConsumer();
        consumer.addConsumer(address(raffle), config.vrfCoordinator, config.subscriptionId, config.account);

        return (raffle, helperConfig);
    }
}
