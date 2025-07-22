// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;
/* solhint-disable no-console */

import {IVRFSubscriptionV2Plus} from
    "../lib/foundry-chainlink-toolkit/lib/chainlink-brownie-contracts/contracts/src/v0.8/dev/interfaces/IVRFSubscriptionV2Plus.sol";

import {Script, console } from "../lib/forge-std/src/Script.sol";
import {Loterie} from "../src/Loterie.sol";
import {SGOLD} from "../src/StableCoin.sol";

contract DeployProtocolScript is Script {
    IVRFSubscriptionV2Plus public vrfCoordinator = IVRFSubscriptionV2Plus(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B);
    function setUp() public {
        
    }

    function run() external {
        vm.startBroadcast();

        uint256 subId = vrfCoordinator.createSubscription();
        console.log("Subscription created with ID:", subId);
        vrfCoordinator.fundSubscriptionWithNative{value: 0.1 ether}(subId);

        Loterie loterie = new Loterie(subId, address(vrfCoordinator));
        console.log("Lotterie contract deployed at:", address(loterie));

        vrfCoordinator.addConsumer(subId, address(loterie));
        console.log("Consumer added to VRF Coordinator");

        // Deploy SGOLD contract
        address treasury = msg.sender; // Use the deployer's address as the treasury
        SGOLD stableCoin = new SGOLD(address(loterie), treasury);
        console.log("SGOLD contract deployed at:", address(stableCoin));

        // Transfer ownership of the Loterie contract to the SGOLD contract
        loterie.transferOwnership(address(stableCoin));
        console.log("Ownership of Loterie contract transferred to SGOLD contract");

        vm.stopBroadcast();
        
    }
}
