// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {HelperConfig, Constants} from "../script/HelperConfig.s.sol";
import {RaffleScript} from "../script/Raffle.s.sol";
import {Raffle} from "../src/Raffle.sol";

event EnteredRaffle(address indexed player);

event WinnerPicked(address indexed winner);

contract RaffleTest is Test, Constants {
    Raffle raffle;
    HelperConfig helperConfig;

    address PLAYER = makeAddr("player");
    uint256 constant STARTING_BALANCE = 10 ether;

    uint256 entryFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;

    function setUp() external {
        RaffleScript deployer = new RaffleScript();
        (raffle, helperConfig) = deployer.deploy();

        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entryFee = config.entryFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;

        vm.deal(PLAYER, STARTING_BALANCE);
    }

    modifier playerEntersRaffle() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entryFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function test_RaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    // enterRaffle Test Start
    function test_RaffleRevertsWhenFundIsInsufficient() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__InsufficientFeeToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    // Arrange, Act, Assert
    function test_RaffleRecordsPlayer() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entryFee}();
        address player = raffle.getPlayer(0);
        assert(player == PLAYER);
    }

    function test_RaffleEmitsEventWhenPlayerEntersRaffle() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entryFee}();
    }

    function test_RaffleBlocksPlayerWhenRaffleIsCalculating() public playerEntersRaffle {
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entryFee}();
    }
    // enterRaffle Test End

    // checkUpkeep Test Start
    function test_checkUpKeepReturnsFalseWhenThereIsNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function test_checkUpKeepReturnsFalseWhenRaffleIsNotOpen() public playerEntersRaffle {
        raffle.performUpkeep("");

        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function test_checkUpKeepReturnsFalseWhenEnoughTimeHasNotPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entryFee}();

        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function test_checkUpKeepReturnsTrue() public playerEntersRaffle {
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(upkeepNeeded);
    }
    // checkUpkeep Test End

    // performUpkeep Test Start
    function test_performUpkeepRunsWhenCheckUpKeepReturnsTrue() public playerEntersRaffle {
        raffle.performUpkeep("");
    }

    function test_performUpkeepRevertsWhenCheckUpKeepReturnsFalse() public skipFork {
        uint256 currentBalance = 0;
        uint256 numberOfPlayers = 0;
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entryFee}();
        currentBalance = currentBalance + entryFee;
        numberOfPlayers = 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numberOfPlayers, raffleState
            )
        );
        raffle.performUpkeep("");
    }

    function test_performUpkeepUpdatesRaffleStateAndEmitsEvent() public playerEntersRaffle {
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }
    // performUpkeep Test End

    // fulfillRandomWords Test Start
    // function test_fulfillRandomWordsRunsAfterPerformUpkeep() public {
    //     vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
    //     VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(0, address(raffle));

    //     vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
    //     VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(1, address(raffle));
    // }

    function test_fulfillRandomWordsRunsAfterPerformUpkeep(uint256 requestId) public playerEntersRaffle skipFork {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(requestId, address(raffle));
    }

    function test_fulfillRandomWordsPicksAWinner() public playerEntersRaffle skipFork {
        uint256 additionalPlayers = 3;
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        for (uint256 i = startingIndex; i < startingIndex + additionalPlayers; i++) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, 1 ether);
            raffle.enterRaffle{value: entryFee}();
        }
        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entryFee * (additionalPlayers + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(endingTimeStamp > startingTimeStamp);
        assert(winnerBalance == winnerStartingBalance + prize);
    }
    // fulfillRandomWords Test End
}
