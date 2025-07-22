// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// import {VRFConsumerBaseV2Plus} from "../lib/chainlink-evm/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
// import {VRFV2PlusClient} from "../lib/chainlink-evm/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {VRFConsumerBaseV2Plus} from
    "../lib/foundry-chainlink-toolkit/lib/chainlink-brownie-contracts/contracts/src/v0.8/dev/vrf/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from
    "../lib/foundry-chainlink-toolkit/lib/chainlink-brownie-contracts/contracts/src/v0.8/dev/vrf/libraries/VRFV2PlusClient.sol";

contract Loterie is VRFConsumerBaseV2Plus {
    // VRF
    uint256 s_subscriptionId;
    address public vrfCoordinator;
    uint8 public rollingStatus = 0; // 0: not rolled, 1: rolling, 2: rolled
    
    // Lotterie 
    uint256 public player_count = 0;
    uint8 internal min_players = 10;
    bool public is_active = false;
    address public lastWinner;
    uint256 public rand;

    mapping(uint256 => address) public players;

    event RequestSent(uint256 requestId, uint256 playerCount);

    error UnreachedParticipationFees(address player, uint256 given_amount, uint256 required_amount);
    error NotEnoughPlayers(uint256 player_count, uint8 min_players);
    error LotterieNotActive();
    error LotterieAlreadyActive();
    error LotterieNotEmpty();
    error TransferFailed();
    error LotterieNotRolledYet();
    error NotWinner(address player, address winner);

    constructor(uint256 _s_subscriptionId, address _vrfCoordinator) VRFConsumerBaseV2Plus(_vrfCoordinator) {
        s_subscriptionId = _s_subscriptionId;
        vrfCoordinator = _vrfCoordinator;
    }

    function addPlayer(address player) public payable onlyOwner() {
        require(is_active, LotterieNotActive());
        players[player_count] = player;
        player_count++;
    }

    function startLotterie() public onlyOwner() {
        require(!is_active, LotterieAlreadyActive());
        require(address(this).balance == 0, LotterieNotEmpty());

        for (uint256 i = 0; i < player_count; i++) {
            delete players[i];
        }

        player_count = 0;
        
        is_active = true;
    }

    function endLotterie() public onlyOwner() {
        require(is_active, LotterieNotActive());
        require(player_count >= min_players, NotEnoughPlayers(player_count, min_players));
        is_active = false;
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
                subId: s_subscriptionId,
                requestConfirmations: 3,
                callbackGasLimit: 400000,
                numWords: 1,
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}))
            })
        );
        rollingStatus = 1; // Reset rolling status
        emit RequestSent(requestId, player_count);
    }

    function fulfillRandomWords(uint256 , uint256[] memory randomWords) internal override {// Not used requestId

        rand = randomWords[0];
        uint256 winnerIndex = randomWords[0] % player_count;
        lastWinner = players[winnerIndex];
        rollingStatus = 2;
    }

    function claimReward() public {
        require(rollingStatus == 2, LotterieNotRolledYet());
        require(msg.sender == lastWinner, NotWinner(msg.sender, lastWinner));
        
        uint256 reward = address(this).balance;
        (bool success, ) = msg.sender.call{value: reward}("");
        require(success, TransferFailed());
        
        rollingStatus = 0;
    }

}
