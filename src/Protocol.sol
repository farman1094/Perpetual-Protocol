// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;
// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract Protocol is ReentrancyGuard {
    error Protocol__NeedsMoreThanZero();
    error Protocol__DepositFailed();

    /**
     * @title PrepProtocol
     * @author Mohd Farman
     * This system is designed to be as minimal as possible.
     */
    struct Position {
        uint256 typeOf; // Define type: LONG (0) / SHORT (1 )
        uint256 size; // BorrowedMoney
        uint256 sizeOfToken; //Token Purchased from Borrowed Money
    }

    Position[] public positions;
    address immutable i_acceptedCollateral;

    //////////////////////////
    // State variables
    //////////////////////////

    address constant BTC = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43; // Price Feed adress for BTC/USD
    uint256 constant LONG = 0;
    uint256 constant SHORT = 1;
    uint256 constant leverageRate = 15; // Leverage rate if 10$ collatel can open the position for 150

    mapping(address => uint256) s_collateralOfUser;

    // Events
    event CollateralDeposited(address indexed sender, uint256 amount);

    //////////////////////////
    // Modifiers
    //////////////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert Protocol__NeedsMoreThanZero();
        _;
    }

    //////////////////////////
    // External Functions
    //////////////////////////

    // Prior using this function provide allowance to this contract.
    function depositCollateral(uint256 amount) external moreThanZero(amount) nonReentrant {
        // CEI
        s_collateralOfUser[msg.sender] += amount;
        emit CollateralDeposited(msg.sender, amount);
        bool success = IERC20(i_acceptedCollateral).transferFrom(msg.sender, address(this), amount);
        if (!success) revert Protocol__DepositFailed();
    }

    function openingPosition() external {}

    function redeemCollateral() external {}

    //    latestRoundData()  (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function getPriceOfBtc() external view returns (int256 price) {
        (, int256 answer,,,) = AggregatorV3Interface(BTC).latestRoundData();
        // return uint256(answer);
        return answer;
    }
}
