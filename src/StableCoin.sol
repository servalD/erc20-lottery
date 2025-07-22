// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "../lib/foundry-chainlink-toolkit/lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Loterie} from "./Loterie.sol";

contract SGOLD is ERC20, Ownable {
    AggregatorV3Interface internal XAUFeed;
    AggregatorV3Interface internal ETHFeed;
    Loterie public immutable LOTERIE;
    address payable public immutable TREASURY;

    mapping(address => uint256) public eth_balances;
    mapping(address => uint256) public sgold_balances;

    uint256 public constant PROTOCOL_FEES = 20; // 20%
    uint256 public constant LOTERIE_FEES = 10; // 10%

    error NoETHSent(address user);

    constructor(address _loterie, address _treasury) ERC20("SGold", "SG") Ownable(msg.sender) {
      LOTERIE = Loterie(_loterie);
      TREASURY = payable(_treasury);
      
      XAUFeed = AggregatorV3Interface(
            0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea
        );
      ETHFeed = AggregatorV3Interface(
            0x694AA1769357215DE4FAC081bf1f309aDC325306
        );
    }

    function ethToSgold(uint256 ethAmount) public view returns (uint256) {
        (, int256 xauPrice, , , ) = XAUFeed.latestRoundData();
        (, int256 ethPrice, , , ) = ETHFeed.latestRoundData();
        // Facteur de correction pour le nombre de decimals de difference entre les deux prix
        uint8 xauDesc = XAUFeed.decimals();
        uint8 ethDesc = ETHFeed.decimals();
        int256 factor = int256(10 ** (xauDesc - ethDesc));
        if (factor > 0) {
            xauPrice = xauPrice * factor;
        } else if (factor < 0) {
            ethPrice = ethPrice / (-factor);
        } 
        return (ethAmount * uint256(xauPrice)) / uint256(ethPrice);
    }

    receive() external payable {
        mint();
    }

    function mint() public payable {
        require(msg.value > 0, NoETHSent(msg.sender));
        // Récupaire les fonts pour chaques partie
        uint256 protocolFees = (msg.value * PROTOCOL_FEES) / 100;
        uint256 loterieFees = (msg.value * LOTERIE_FEES) / 100;
        uint256 ethForMint = msg.value - protocolFees - loterieFees;
        uint256 amountToMint = ethToSgold(ethForMint);
        // envoi les fonds a la LOTERIE
        LOTERIE.addPlayer{value: loterieFees}(msg.sender);
        // envoi les fonds sur TREASURY
        TREASURY.transfer(protocolFees);
        // Mint les tokens
        _mint(msg.sender, amountToMint);
        // Mettre a jour le solde
        sgold_balances[msg.sender] += amountToMint;
        eth_balances[msg.sender] += ethForMint;

    }

    function withdraw() external onlyOwner {
        uint256 balance = eth_balances[msg.sender];
        require(balance > 0, "No balance to withdraw");
        // burn les tokens de l'utilisateur
        uint256 sgoldAmount = sgold_balances[msg.sender];
        _burn(msg.sender, sgoldAmount);
        // Mettre a jour les soldes
        eth_balances[msg.sender] = 0;
        sgold_balances[msg.sender] = 0;
        // Transfert des fonds
        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "Transfer failed");
        TREASURY.transfer(balance);
    }
}
