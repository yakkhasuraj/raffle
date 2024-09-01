// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {DevOpsTools} from "@foundry-devops/DevOpsTools.sol";
import {HelperConfig, Constants} from "./HelperConfig.s.sol";
import {LinkToken} from "../test/LinkToken.sol";

contract CreateSubscription is Script {
    function run() external {
        createSubscriptionWithConfig();
    }

    function createSubscriptionWithConfig() public returns (uint256, address) {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        address account = helperConfig.getConfig().account;
        (uint256 subscriptionId,) = createSubscription(vrfCoordinator, account);
        return (subscriptionId, vrfCoordinator);
    }

    function createSubscription(address vrfCoordinator, address account) public returns (uint256, address) {
        console.log("Creating subscription on chain:", block.chainid);

        vm.startBroadcast(account);

        uint256 subscriptionId = VRFCoordinatorV2_5Mock(vrfCoordinator).createSubscription();

        vm.stopBroadcast();

        console.log("Your subscription id is:", subscriptionId);
        return (subscriptionId, vrfCoordinator);
    }
}

contract FundSubscription is Script, Constants {
    uint256 public constant FUND_AMOUNT = 3 ether;

    function run() external {
        fundSubscriptionWithConfig();
    }

    function fundSubscriptionWithConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        uint256 subscriptionId = helperConfig.getConfig().subscriptionId;
        address linkToken = helperConfig.getConfig().linkToken;
        address account = helperConfig.getConfig().account;
        fundSubscription(vrfCoordinator, subscriptionId, linkToken, account);
    }

    function fundSubscription(address vrfCoordinator, uint256 subscriptionId, address linkToken, address account)
        public
    {
        console.log("Funding subscription:", subscriptionId);

        if (block.chainid == LOCAL_CHAIN_ID) {
            vm.startBroadcast();

            VRFCoordinatorV2_5Mock(vrfCoordinator).fundSubscription(subscriptionId, FUND_AMOUNT * 100);

            vm.stopBroadcast();
        } else {
            vm.startBroadcast(account);

            LinkToken(linkToken).transferAndCall(vrfCoordinator, FUND_AMOUNT, abi.encode(subscriptionId));

            vm.stopBroadcast();
        }
    }
}

contract AddConsumer is Script {
    function run() external {
        address recentDeployment = DevOpsTools.get_most_recent_deployment("Raffle", block.chainid);
        addConsumerWithConfig(recentDeployment);
    }

    function addConsumerWithConfig(address recentDeployment) public {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        uint256 subscriptionId = helperConfig.getConfig().subscriptionId;
        address account = helperConfig.getConfig().account;
        addConsumer(recentDeployment, vrfCoordinator, subscriptionId, account);
    }

    function addConsumer(address contractToAddToVrf, address vrfCoordinator, uint256 subscriptionId, address account)
        public
    {
        console.log("Adding consumer:", contractToAddToVrf);

        vm.startBroadcast(account);

        VRFCoordinatorV2_5Mock(vrfCoordinator).addConsumer(subscriptionId, contractToAddToVrf);

        vm.stopBroadcast();
    }
}
