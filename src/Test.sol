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
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";


contract Protocol is ReentrancyGuard {

error Protocol__NeedsMoreThanZero();
error Protocol__DepositFailed();
error Protocol__LeverageLimitReached();


/**
 * @title PrepProtocol
 * @author Mohd Farman
 * This system is designed to be as minimal as possible.
 */

    struct Position  {
        uint256 size;   // BorrowedMoney
        uint256 sizeOfToken; //Token Purchased from Borrowed Money
        bool isLong; // Define type: LONG (True) / SHORT (false) 
    }

    struct LongPosition {
    uint256 totalSize;
    uint256 totalSizeOfToken;
    }

    struct ShortPosition {
    uint256 totalSize;
    uint256 totalSizeOfToken;
    }

    mapping(address => Position) positions;  
    LongPosition public longPosition; 
    ShortPosition public shortPosition;

    address immutable i_acceptedCollateral;


    //////////////////////////
    // State variables 
    //////////////////////////

    address constant BTC = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43; // Price Feed adress for BTC/USD
    uint256 constant LEVERAGE_RATE = 15; // Leverage rate if 10$ can open the position for $150
    uint256 constant PRICE_PRECISION = 1e10;
    uint256 constant PRECISION = 1e18;

    mapping(address => uint256) s_collateralOfUser;
    uint256 private s_numOfOpenPositions;


    // Events
    event CollateralDeposited (address indexed sender, uint256 amount);
    event PositionOpened (address indexed sender, uint256 size);



    //////////////////////////
    // Modifiers
    //////////////////////////

    modifier moreThanZero(uint256 amount) {
        if(amount == 0) revert Protocol__NeedsMoreThanZero();
        _;
    }


    constructor(address collateralAddress) {
        i_acceptedCollateral = collateralAddress;
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

    function openingPosition(uint256 _size, bool _isLong) moreThanZero(_size) external {
        // CEI
        bool success = _checkLeverageFactor(msg.sender, _size);
        if (!success) revert Protocol__LeverageLimitReached();
        uint256 numOfToken = _getNumOfTokenByAmount(_size);
        if(_isLong) { // position for long
        positions[msg.sender] = Position({
            size: _size,
            sizeOfToken: numOfToken,
            isLong: true
        });
        } else { //position for short
           positions[msg.sender] = Position({
            size: _size,
            sizeOfToken: numOfToken,
            isLong: false
        });
        }
        emit PositionOpened( msg.sender, _size);
        // get the total of short or long;
        if(positions[msg.sender].isLong){
            longPosition.totalSize += _size;
            longPosition.totalSizeOfToken += numOfToken;
        } else {
            shortPosition.totalSize += _size;
            shortPosition.totalSizeOfToken += numOfToken;
        } 
        
        s_numOfOpenPositions++;
    } 

    function redeemCollateral() external {}



    //////////////////////////
    // Internals Functions
    //////////////////////////


    // to check leverage percentage is as per approved
    /**@dev we are not checking if _size already exist */
    function _checkLeverageFactor(address sender, uint256 _size) internal view returns(bool) {
        uint256 collateralOfUser =  s_collateralOfUser[sender];
        uint256 sizeLimit = collateralOfUser * LEVERAGE_RATE;
        bool success;
        if(sizeLimit >= _size){
             success = true;
        }else {
            success = false;
        }
        return success;
    }

    // According to size how much token get // (size should be in 1e18)
    function _getNumOfTokenByAmount(uint256 amount) internal view returns(uint256) {
     uint256 priceOfBtc =  _getPriceOfBtc();
     uint256 numOfToken =  (amount * PRECISION)/ priceOfBtc;
     return numOfToken;
    }

    function _getPriceOfBtc() internal view returns(uint256 price) {
    (, int256 answer,,,) = AggregatorV3Interface(BTC).latestRoundData();
     price = uint256(answer); // price return amount with e8 (correcting it)
    return price * PRICE_PRECISION;
    }

    //////////////////////////
    // Getters and View function
    //////////////////////////

    function getPriceOfBtc() public view returns(uint256 price) {
        return _getPriceOfBtc();
    }
    function getNumOfTokenByAmount(uint256 amount) public view returns (uint256) {
         return _getNumOfTokenByAmount(amount);

    } 
    function checkLeverageFactor(address sender, uint256 _size) public view returns(bool) {
        return _checkLeverageFactor(sender,_size);
    }

}
