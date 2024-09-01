// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

event EnteredRaffle(address indexed player);

event RequestedRaffleWinner(uint256 indexed requestId);

event WinnerPicked(address indexed winner);

/**
 * @title A sample Raffle contract
 * @author Suraj Yakkha
 * @notice You can use this contract for creating a sample raffle
 * @dev Implements Chainlink VRF(Verifiable Random Function)
 */
contract Raffle is VRFConsumerBaseV2Plus {
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entryFee;
    // @dev Duration of lottery in seconds
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    error Raffle__InsufficientFeeToEnterRaffle();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);

    constructor(
        uint256 entryFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entryFee = entryFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function getEntryFee() external view returns (uint256) {
        return i_entryFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function enterRaffle() external payable {
        // require(msg.value < i_entryFee, "Not enough ETH sent");
        if (msg.value < i_entryFee) {
            revert Raffle__InsufficientFeeToEnterRaffle();
        }
        // require(msg.value < i_entryFee, Raffle__InsufficientFeeToEnterRaffle()); // Available with via-IR compilation pipeline

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
    }

    /**
     * @dev Implements the logic that will be executed offchain to see if performUpkeep should be executed
     * When checkUpkeep returns true, the Chainlink Automation Network calls performUpkeep onchain
     */
    function checkUpkeep(bytes memory /* checkData */ )
        public
        view
        returns (
            /* override */
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) > i_interval;
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "");
    }

    function performUpkeep(bytes calldata /* performData */ ) external /* override */ {
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }

        s_raffleState = RaffleState.CALCULATING;

        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_keyHash,
            subId: i_subscriptionId,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: i_callbackGasLimit,
            numWords: NUM_WORDS,
            // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
            extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
        });

        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RequestedRaffleWinner(requestId);
    }

    // function pickWinner() external {
    //     if ((block.timestamp - s_lastTimeStamp) < i_interval) {
    //         revert();
    //     }

    //     s_raffleState = RaffleState.CALCULATING;

    //     VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
    //         keyHash: i_keyHash,
    //         subId: i_subscriptionId,
    //         requestConfirmations: REQUEST_CONFIRMATIONS,
    //         callbackGasLimit: i_callbackGasLimit,
    //         numWords: NUM_WORDS,
    //         // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
    //         extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
    //     });

    //     uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
    // }

    // CEI -  Check, Effects, Interactions
    function fulfillRandomWords(uint256, /* requestId */ uint256[] calldata randomWords) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;

        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(recentWinner);

        (bool success,) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }
}
