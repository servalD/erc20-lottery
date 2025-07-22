// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Loterie} from "../src/Loterie.sol";
import {VRFCoordinatorV2_5Mock} from "../lib/chainlink-evm/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract LoterieTest is Test {
    Loterie public loterie;
    VRFCoordinatorV2_5Mock public vrfCoordinator;
    
    address public owner = makeAddr("owner");
    address public player1 = makeAddr("player1");
    address public player2 = makeAddr("player2");
    address public player3 = makeAddr("player3");
    address public player4 = makeAddr("player4");
    address public player5 = makeAddr("player5");
    address public player6 = makeAddr("player6");
    address public player7 = makeAddr("player7");
    address public player8 = makeAddr("player8");
    address public player9 = makeAddr("player9");
    address public player10 = makeAddr("player10");
    
    // VRF Mock parameters
    uint96 public constant BASE_FEE = 0.25 ether;
    uint96 public constant GAS_PRICE_LINK = 1e9;
    int256 public constant WEI_PER_UNIT_LINK = 4e15;

    function setUp() public {
        vm.deal(owner, 100 ether);
        // Deploy VRF Coordinator Mock
        vrfCoordinator = new VRFCoordinatorV2_5Mock(BASE_FEE, GAS_PRICE_LINK, WEI_PER_UNIT_LINK);
        
        // Create subscription
        uint256 subId = vrfCoordinator.createSubscription();
        
        // Fund subscription
        vrfCoordinator.fundSubscription(subId, 3 ether);
        
        // Deploy Loterie contract
        vm.prank(owner);
        loterie = new Loterie(subId, address(vrfCoordinator));
        
        // Add consumer to VRF subscription
        vrfCoordinator.addConsumer(subId, address(loterie));
        
        // Give ETH to test accounts
        vm.deal(player1, 10 ether);
        vm.deal(player2, 10 ether);
        vm.deal(player3, 10 ether);
        vm.deal(player4, 10 ether);
        vm.deal(player5, 10 ether);
        vm.deal(player6, 10 ether);
        vm.deal(player7, 10 ether);
        vm.deal(player8, 10 ether);
        vm.deal(player9, 10 ether);
        vm.deal(player10, 10 ether);
    }

    function testConstructor() public {
        assertEq(loterie.vrfCoordinator(), address(vrfCoordinator));
        assertEq(loterie.player_count(), 0);
        assertEq(loterie.rollingStatus(), 0);
        assertFalse(loterie.is_active());
    }

    function testStartLotterie() public {
        vm.prank(owner);
        loterie.startLotterie();
        
        assertTrue(loterie.is_active());
        assertEq(loterie.player_count(), 0);
    }

    function testStartLoterieAlreadyActive() public {
        vm.startPrank(owner);
        loterie.startLotterie();
        
        vm.expectRevert(abi.encodeWithSelector(Loterie.LotterieAlreadyActive.selector));
        loterie.startLotterie();
        vm.stopPrank();
    }

    function testStartLoterieWithBalance() public {
        // Send ETH to the contract first
        vm.deal(address(loterie), 1 ether);
        
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Loterie.LotterieNotEmpty.selector));
        loterie.startLotterie();
    }

    function testAddPlayer() public {
        vm.startPrank(owner);
        loterie.startLotterie();
        
        loterie.addPlayer{value: 0.1 ether}(player1);
        
        assertEq(loterie.player_count(), 1);
        assertEq(loterie.players(0), player1);
        assertEq(address(loterie).balance, 0.1 ether);
        vm.stopPrank();
    }

    function testAddPlayerLoterieNotActive() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Loterie.LotterieNotActive.selector));
        loterie.addPlayer{value: 0.1 ether}(player1);
    }

    function testAddPlayerOnlyOwner() public {
        vm.prank(owner);
        loterie.startLotterie();
        
        vm.prank(player1);
        vm.expectRevert(); // Should revert because player1 is not owner
        loterie.addPlayer{value: 0.1 ether}(player2);
    }

    function testAddMultiplePlayers() public {
        vm.startPrank(owner);
        loterie.startLotterie();
        
        loterie.addPlayer{value: 0.1 ether}(player1);
        loterie.addPlayer{value: 0.2 ether}(player2);
        loterie.addPlayer{value: 0.3 ether}(player3);
        
        assertEq(loterie.player_count(), 3);
        assertEq(loterie.players(0), player1);
        assertEq(loterie.players(1), player2);
        assertEq(loterie.players(2), player3);
        assertEq(address(loterie).balance, 0.6 ether);
        vm.stopPrank();
    }

    function testEndLoterieNotActive() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Loterie.LotterieNotActive.selector));
        loterie.endLotterie();
    }

    function testEndLoterieNotEnoughPlayers() public {
        vm.startPrank(owner);
        loterie.startLotterie();
        
        // Add only 2 players (minimum is 10)
        loterie.addPlayer{value: 0.1 ether}(player1);
        loterie.addPlayer{value: 0.1 ether}(player2);
        
        vm.expectRevert(abi.encodeWithSelector(Loterie.NotEnoughPlayers.selector, 2, 10));
        loterie.endLotterie();
        vm.stopPrank();
    }

    function testEndLoterieSuccess() public {
        vm.startPrank(owner);
        loterie.startLotterie();
        
        // Add minimum required players (10)
        addAllPlayers();
        
        vm.expectEmit(true, false, false, true);
        emit Loterie.RequestSent(1, 10); // requestId should be 1, playerCount is 10
        
        loterie.endLotterie();
        
        assertFalse(loterie.is_active());
        assertEq(loterie.rollingStatus(), 1); // Rolling
        vm.stopPrank();
    }

    function testFullLoterieFlow() public {
        vm.startPrank(owner);
        loterie.startLotterie();
        
        // Add minimum required players (10)
        addAllPlayers();
        
        uint256 totalPrize = address(loterie).balance;
        assertEq(totalPrize, 1 ether);
        
        // End lottery and request randomness
        loterie.endLotterie();
        vm.stopPrank();
        
        // Simulate VRF callback
        uint256 requestId = 1;
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 123456789; // Random number
        
        uint256 expectedWinnerIndex = randomWords[0] % 10;
        address expectedWinner;
        
        if (expectedWinnerIndex == 0) expectedWinner = player1;
        else if (expectedWinnerIndex == 1) expectedWinner = player2;
        else if (expectedWinnerIndex == 2) expectedWinner = player3;
        else if (expectedWinnerIndex == 3) expectedWinner = player4;
        else if (expectedWinnerIndex == 4) expectedWinner = player5;
        else if (expectedWinnerIndex == 5) expectedWinner = player6;
        else if (expectedWinnerIndex == 6) expectedWinner = player7;
        else if (expectedWinnerIndex == 7) expectedWinner = player8;
        else if (expectedWinnerIndex == 8) expectedWinner = player9;
        else expectedWinner = player10;
        
        uint256 winnerBalanceBefore = expectedWinner.balance;
        
        // Fulfill randomness
        vrfCoordinator.fulfillRandomWords(requestId, address(loterie));
        
        // Check results after VRF fulfillment
        assertEq(loterie.lastWinner(), expectedWinner);
        assertEq(loterie.rollingStatus(), 2); // Rolled state
        assertEq(loterie.rand(), randomWords[0]);
        assertEq(expectedWinner.balance, winnerBalanceBefore); // Balance unchanged before claim
        assertEq(address(loterie).balance, totalPrize); // Prize still in contract
        
        // Winner claims reward
        vm.prank(expectedWinner);
        loterie.claimReward();
        
        // Check results after claim
        assertEq(loterie.rollingStatus(), 0); // Reset to 0 after claim
        assertEq(expectedWinner.balance, winnerBalanceBefore + totalPrize);
        assertEq(address(loterie).balance, 0);
    }

    function testResetPlayersOnStart() public {
        vm.startPrank(owner);
        
        // First lottery cycle
        loterie.startLotterie();
        addAllPlayers();
        
        assertEq(loterie.player_count(), 10);
        
        // End first lottery
        loterie.endLotterie();
        vm.stopPrank();
        
        // Fulfill VRF
        vrfCoordinator.fulfillRandomWords(1, address(loterie));
        
        // Winner claims reward
        vm.prank(loterie.lastWinner());
        loterie.claimReward();
        
        // Start new lottery
        vm.prank(owner);
        loterie.startLotterie();
        
        // Players should be reset
        assertEq(loterie.player_count(), 0);
        assertEq(loterie.players(0), address(0));
        assertEq(loterie.players(1), address(0));
        assertEq(loterie.players(2), address(0));
        assertTrue(loterie.is_active());
    }

    function testMultipleLoteryCycles() public {
        for (uint256 i = 0; i < 3; i++) {
            vm.startPrank(owner);
            loterie.startLotterie();
            
            addAllPlayers();
            
            loterie.endLotterie();
            vm.stopPrank();
            
            // Fulfill VRF with different random numbers
            vrfCoordinator.fulfillRandomWords(i + 1, address(loterie));
            
            assertEq(loterie.rollingStatus(), 2); // Rolled state
            
            // Winner claims reward
            vm.prank(loterie.lastWinner());
            loterie.claimReward();
            
            assertEq(loterie.rollingStatus(), 0);
            assertFalse(loterie.is_active());
        }
    }

    function testStateTransitions() public {
        // Initial state
        assertEq(loterie.rollingStatus(), 0); // Not rolled
        assertFalse(loterie.is_active());
        
        vm.startPrank(owner);
        
        // Start lottery
        loterie.startLotterie();
        assertTrue(loterie.is_active());
        assertEq(loterie.rollingStatus(), 0); // Still not rolled
        
        // Add players and end
        addAllPlayers();
        
        loterie.endLotterie();
        assertFalse(loterie.is_active());
        assertEq(loterie.rollingStatus(), 1); // Rolling
        
        vm.stopPrank();
        
        // Fulfill VRF
        vrfCoordinator.fulfillRandomWords(1, address(loterie));
        assertEq(loterie.rollingStatus(), 2); // Rolled state after VRF fulfillment
        
        // Winner claims reward to complete the cycle
        vm.prank(loterie.lastWinner());
        loterie.claimReward();
        assertEq(loterie.rollingStatus(), 0); // Reset to 0 after claim
    }

    function testCannotEndLoterieWithRollingStatus() public {
        vm.startPrank(owner);
        loterie.startLotterie();
        
        // Add minimum required players (10)
        addAllPlayers();
        
        // End lottery once
        loterie.endLotterie();
        
        // Try to end lottery again while rolling
        vm.expectRevert(abi.encodeWithSelector(Loterie.LotterieNotActive.selector));
        loterie.endLotterie();
        
        vm.stopPrank();
    }

    function testCannotAddPlayerAfterEnd() public {
        vm.startPrank(owner);
        loterie.startLotterie();
        
        // Add minimum required players (10)
        addAllPlayers();
        
        // End lottery
        loterie.endLotterie();
        
        // Try to add another player after ending
        vm.expectRevert(abi.encodeWithSelector(Loterie.LotterieNotActive.selector));
        loterie.addPlayer{value: 0.1 ether}(player1);
        
        vm.stopPrank();
    }

    function testExactlyMinimumPlayers() public {
        vm.startPrank(owner);
        loterie.startLotterie();
        
        // Add exactly 10 players (minimum)
        for (uint256 i = 1; i <= 10; i++) {
            address player = makeAddr(string.concat("player", vm.toString(i)));
            vm.deal(player, 1 ether);
            loterie.addPlayer{value: 0.1 ether}(player);
        }
        
        assertEq(loterie.player_count(), 10);
        
        // Should be able to end lottery
        loterie.endLotterie();
        assertFalse(loterie.is_active());
        assertEq(loterie.rollingStatus(), 1);
        
        vm.stopPrank();
    }

    function testMoreThanMinimumPlayers() public {
        vm.startPrank(owner);
        loterie.startLotterie();
        
        // Add more than minimum players (15 players)
        address[] memory extraPlayers = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            extraPlayers[i] = makeAddr(string.concat("extraPlayer", vm.toString(i)));
            vm.deal(extraPlayers[i], 1 ether);
        }
        
        // Add the original 10 players
        addAllPlayers();
        
        // Add 5 extra players
        for (uint256 i = 0; i < 5; i++) {
            loterie.addPlayer{value: 0.1 ether}(extraPlayers[i]);
        }
        
        assertEq(loterie.player_count(), 15);
        
        // Should be able to end lottery
        loterie.endLotterie();
        assertFalse(loterie.is_active());
        assertEq(loterie.rollingStatus(), 1);
        
        vm.stopPrank();
    }

    function testDifferentPaymentAmounts() public {
        vm.startPrank(owner);
        loterie.startLotterie();
        
        // Add players with different payment amounts
        loterie.addPlayer{value: 0.1 ether}(player1);
        loterie.addPlayer{value: 0.5 ether}(player2);
        loterie.addPlayer{value: 1.0 ether}(player3);
        loterie.addPlayer{value: 2.0 ether}(player4);
        loterie.addPlayer{value: 0.01 ether}(player5);
        loterie.addPlayer{value: 10 ether}(player6);
        loterie.addPlayer{value: 0.001 ether}(player7);
        loterie.addPlayer{value: 0.1 ether}(player8);
        loterie.addPlayer{value: 0.1 ether}(player9);
        loterie.addPlayer{value: 0.1 ether}(player10);
        
        uint256 expectedTotal = 0.1 ether + 0.5 ether + 1.0 ether + 2.0 ether + 0.01 ether + 10 ether + 0.001 ether + 0.1 ether + 0.1 ether + 0.1 ether;
        
        assertEq(address(loterie).balance, expectedTotal);
        assertEq(loterie.player_count(), 10);
        
        vm.stopPrank();
    }

    function testClaimRewardNotRolledYet() public {
        vm.startPrank(owner);
        loterie.startLotterie();
        addAllPlayers();
        vm.stopPrank();
        
        // Try to claim reward before lottery is ended
        vm.prank(player1);
        vm.expectRevert(abi.encodeWithSelector(Loterie.LotterieNotRolledYet.selector));
        loterie.claimReward();
        
        vm.prank(owner);
        loterie.endLotterie();
        
        // Try to claim reward while rolling (status = 1)
        vm.prank(player1);
        vm.expectRevert(abi.encodeWithSelector(Loterie.LotterieNotRolledYet.selector));
        loterie.claimReward();
    }

    function testClaimRewardNotWinner() public {
        vm.startPrank(owner);
        loterie.startLotterie();
        addAllPlayers();
        loterie.endLotterie();
        vm.stopPrank();
        
        // Fulfill VRF
        vrfCoordinator.fulfillRandomWords(1, address(loterie));
        
        address winner = loterie.lastWinner();
        address notWinner = (winner == player1) ? player2 : player1;
        
        // Try to claim reward as non-winner
        vm.prank(notWinner);
        vm.expectRevert(abi.encodeWithSelector(Loterie.NotWinner.selector, notWinner, winner));
        loterie.claimReward();
    }

    function testClaimRewardOnlyOnce() public {
        vm.startPrank(owner);
        loterie.startLotterie();
        addAllPlayers();
        loterie.endLotterie();
        vm.stopPrank();
        
        // Fulfill VRF
        vrfCoordinator.fulfillRandomWords(1, address(loterie));
        
        address winner = loterie.lastWinner();
        uint256 winnerBalanceBefore = winner.balance;
        uint256 prize = address(loterie).balance;
        
        // Winner claims reward
        vm.prank(winner);
        loterie.claimReward();
        
        assertEq(winner.balance, winnerBalanceBefore + prize);
        assertEq(address(loterie).balance, 0);
        assertEq(loterie.rollingStatus(), 0);
        
        // Try to claim again (should fail because rollingStatus is now 0)
        vm.prank(winner);
        vm.expectRevert(abi.encodeWithSelector(Loterie.LotterieNotRolledYet.selector));
        loterie.claimReward();
    }

    function testClaimRewardResetsState() public {
        vm.startPrank(owner);
        loterie.startLotterie();
        addAllPlayers();
        loterie.endLotterie();
        vm.stopPrank();
        
        // Fulfill VRF
        vrfCoordinator.fulfillRandomWords(1, address(loterie));
        
        // Verify state before claim
        assertEq(loterie.rollingStatus(), 2);
        assertGt(address(loterie).balance, 0);
        
        address winner = loterie.lastWinner();
        
        // Winner claims reward
        vm.prank(winner);
        loterie.claimReward();
        
        // Verify state after claim
        assertEq(loterie.rollingStatus(), 0); // Reset to initial state
        assertEq(address(loterie).balance, 0); // All funds transferred
        assertFalse(loterie.is_active()); // Still inactive
    }

    function testClaimRewardWithDifferentPrizeAmounts() public {
        vm.startPrank(owner);
        loterie.startLotterie();
        
        // Add players with different payment amounts to create a larger prize
        loterie.addPlayer{value: 0.1 ether}(player1);
        loterie.addPlayer{value: 0.5 ether}(player2);
        loterie.addPlayer{value: 1.0 ether}(player3);
        loterie.addPlayer{value: 2.0 ether}(player4);
        loterie.addPlayer{value: 0.01 ether}(player5);
        loterie.addPlayer{value: 10 ether}(player6);
        loterie.addPlayer{value: 0.001 ether}(player7);
        loterie.addPlayer{value: 0.1 ether}(player8);
        loterie.addPlayer{value: 0.1 ether}(player9);
        loterie.addPlayer{value: 0.1 ether}(player10);
        
        uint256 totalPrize = address(loterie).balance;
        
        loterie.endLotterie();
        vm.stopPrank();
        
        // Fulfill VRF
        vrfCoordinator.fulfillRandomWords(1, address(loterie));
        
        address winner = loterie.lastWinner();
        uint256 winnerBalanceBefore = winner.balance;
        
        // Winner claims reward
        vm.prank(winner);
        loterie.claimReward();
        
        // Verify the exact prize amount was transferred
        assertEq(winner.balance, winnerBalanceBefore + totalPrize);
        assertEq(address(loterie).balance, 0);
    }

    // pour la tresorerie
    receive() external payable {}

    function addAllPlayers() internal {
        loterie.addPlayer{value: 0.1 ether}(player1);
        loterie.addPlayer{value: 0.1 ether}(player2);
        loterie.addPlayer{value: 0.1 ether}(player3);
        loterie.addPlayer{value: 0.1 ether}(player4);
        loterie.addPlayer{value: 0.1 ether}(player5);
        loterie.addPlayer{value: 0.1 ether}(player6);
        loterie.addPlayer{value: 0.1 ether}(player7);
        loterie.addPlayer{value: 0.1 ether}(player8);
        loterie.addPlayer{value: 0.1 ether}(player9);
        loterie.addPlayer{value: 0.1 ether}(player10);
    }
}
