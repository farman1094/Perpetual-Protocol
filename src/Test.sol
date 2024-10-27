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
error Protocol__RedeemFailed();
error Protocol__LeverageLimitReached();
error Protocol__UserNotEnoughBalance();
error Protocol__CannotWithdrawWithOpenPosition();
error Protocol__OpenPositionFirst();




/**
 * @title PrepProtocol
 * @author Mohd Farman
 * This system is designed to be as minimal as possible.
 */

    struct Position  {
        uint256 size;   // BorrowedMoney
        uint256 sizeOfToken; //Token Purchased from Borrowed Money
        bool isLong; // Define type: LONG (True) / SHORT (false) 
        bool isInitialized; // Initialized or not
    }

    struct LongPosition {
    uint256 totalSize;
    uint256 totalSizeOfToken;
    }

    struct ShortPosition {
    uint256 totalSize;
    uint256 totalSizeOfToken;
    }




    //////////////////////////
    // State variables 
    //////////////////////////

    address constant BTC = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43; // Price Feed adress for BTC/USD
    uint256 constant LEVERAGE_RATE = 15; // Leverage rate if 10$ can open the position for $150
    uint256 constant PRICE_PRECISION = 1e10;
    uint256 constant PRECISION = 1e18;

    address immutable i_acceptedCollateral;

    mapping(address => Position) positions;  
    mapping(address => uint256)  s_collateralOfUser;
    uint256 private s_numOfOpenPositions;

    LongPosition public longPosition; 
    ShortPosition public shortPosition;

    

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

    function increasePosition(uint256 _size) moreThanZero (_size) external {
            Position memory UserPosition = positions[msg.sender];
            if(UserPosition.isInitialized == false){
                revert Protocol__OpenPositionFirst();
            }
            bool eligible = checkLeverageFactor(msg.sender, _size);
            if (!eligible) revert Protocol__LeverageLimitReached();
            uint256 numOfToken = _getNumOfTokenByAmount(_size);
            positions[msg.sender].size += _size;
            positions[msg.sender].sizeOfToken += numOfToken;

            if(positions[msg.sender].isLong){
            longPosition.totalSize += positions[msg.sender].size;
            longPosition.totalSizeOfToken += positions[msg.sender].sizeOfToken;
        } else {
            shortPosition.totalSize += positions[msg.sender].size;
            shortPosition.totalSizeOfToken += positions[msg.sender].sizeOfToken;
        } 
    }

    function openingPosition(uint256 _size, bool _isLong) moreThanZero(_size) external {
        // CEI
        bool eligible = checkLeverageFactor(msg.sender, _size);
        if (!eligible) revert Protocol__LeverageLimitReached();
        uint256 numOfToken = _getNumOfTokenByAmount(_size);
        if(_isLong) { // position for long
        positions[msg.sender] = Position({
            size: _size,
            sizeOfToken: numOfToken,
            isLong: true,
            isInitialized: true
        });
        } else { //position for short
           positions[msg.sender] = Position({
            size: _size,
            sizeOfToken: numOfToken,
            isLong: false,
            isInitialized: true
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

    //  if user have open position, User can not withdrawal?
    function redeemCollateral(uint256 _amount) external moreThanZero (_amount) nonReentrant {
        Position memory UserPosition = positions[msg.sender];
        if(UserPosition.isInitialized){
            if(UserPosition.size != 0){
                revert Protocol__CannotWithdrawWithOpenPosition();
            }
        }
    
        if(s_collateralOfUser[msg.sender] < _amount) {
            revert Protocol__UserNotEnoughBalance();
            }

        bool success = _redeemCollateral(msg.sender, _amount);
        if(!success) revert Protocol__RedeemFailed();

    }



    //////////////////////////
    // Internals Functions
    //////////////////////////

    // Check Profit or loss of user
        // function checkPnL

    // function transfer(address to, uint256 amount) external returns (bool);


    // Redeem
    function _redeemCollateral(address receiver, uint256 amount) internal returns (bool success) {
        //         s_collateralOfUser[receiver] -= amount;
        success = IERC20(i_acceptedCollateral).transfer(receiver, amount);
        return success;
    }


    // to check leverage percentage is as per approved
    /**@dev we are not checking if _size already exist */
    function _checkLeverageFactorForNew(address sender, uint256 _size) internal view returns(bool) {
        uint256 collateralOfUser = s_collateralOfUser[sender];
        uint256 sizeLimit = collateralOfUser * LEVERAGE_RATE;
        bool eligible;
        if(sizeLimit >= _size){
             eligible = true;
        }else {
            eligible = false;
        }
        return eligible;
    }

    function _checkLeverageFactorForExisting(address sender, uint256 _size) internal view returns(bool) { 
        Position memory UserPosition = positions[sender];
        uint256 collateralOfUser = s_collateralOfUser[sender];
        uint256 sizeLimit = collateralOfUser * LEVERAGE_RATE;
        uint256 sizeAskingFor = _size + UserPosition.size;
        bool eligible;
         if(sizeLimit >= sizeAskingFor){
             eligible = true;
        }else {
            eligible = false;
        }
        return eligible;


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
        if(positions[sender].isInitialized){
        return _checkLeverageFactorForNew(sender,_size);

        } else {
            return _checkLeverageFactorForExisting(sender,_size);
        }
    }

}
