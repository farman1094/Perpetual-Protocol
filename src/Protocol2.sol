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
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Vault} from "src/Vault.sol";

/**
 * @title PrepProtocol
 * @author Mohd Farman
 * This system is designed to be as minimal as possible.
 */


contract Protocol2 is ReentrancyGuard {

// errors
error Protocol__NeedsMoreThanZero();    
error Protocol__FundsNotAvailableForPosition();    

error Protocol__DepositFailed();
error Protocol__RedeemFailed();
error Protocol__LiquidationFailed();
error Protocol__LeverageLimitReached();
error Protocol__UserNotEnoughBalance();
error Protocol__CannotWithdrawWithOpenPosition();
error Protocol__OpenPositionFirst();


using SignedMath for int256;



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


    Vault private vault;

    //////////////////////////
    // State variables 
    //////////////////////////

    address constant BTC = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43; // Price Feed adress for BTC/USD
    uint256 constant LEVERAGE_RATE = 15; // Leverage rate if 10$ can open the position for $150
    uint256 constant LIQUIDITY_THRESHOLD = 15; // if total supply is 100, lp's have to keep 15% in the pool any loses (15+lose) (15 - profit)

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
    event PositionClose (address indexed user, uint256 size);



    //////////////////////////
    // Modifiers
    //////////////////////////

    modifier moreThanZero(uint256 amount) {
        if(amount == 0) revert Protocol__NeedsMoreThanZero();
        _;
    }

    // modifier checkFunds(uint256 _size) {
    //     uint256 availableBorrowing = _liquidityReservesRemaining();
    //     if(availableBorrowing < _size){
    //         revert Protocol__FundsNotAvailableForPosition();
    //     }
    //     _;

    // }


    constructor(address collateralAddress, Vault _vault) {
        i_acceptedCollateral = collateralAddress;
        vault = _vault;
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

    function increasePosition(uint256 _size) moreThanZero (_size)  external {
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
                _increaseTotalLongPosition(_size, numOfToken);
            } else {
                _increaseTotalShortPosition(_size, numOfToken);    
            } 
    }

    function openPosition(uint256 _size, bool _isLong) moreThanZero(_size) external {

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
            _increaseTotalLongPosition(_size, numOfToken);
        } else {
            _increaseTotalShortPosition(_size, numOfToken);    
        } 
        
        s_numOfOpenPositions++;
    } 

    function closePosition() external {
    // CEI
    Position memory userToClose = positions[msg.sender];
    if(userToClose.isInitialized == false){
        revert Protocol__OpenPositionFirst();
    }

  
    int256 PnL = _checkProfitOrLossForUser(msg.sender);
  

    // Update the total Accounting 
        if(userToClose.isLong) {
            longPosition.totalSize -= userToClose.size;
            longPosition.totalSizeOfToken -= userToClose.sizeOfToken;
        } else {
            shortPosition.totalSize -= userToClose.size;
            shortPosition.totalSizeOfToken -= userToClose.sizeOfToken;
        }

    /**@dev reset the mapping */
    delete positions[msg.sender]; //confirm the position
    s_numOfOpenPositions--;
    emit PositionClose(msg.sender, userToClose.size);
    if (PnL > 0){
    
        uint256 profit = PnL.abs(); // convert int to uint256
        s_collateralOfUser[msg.sender] += profit;
        IERC20(i_acceptedCollateral).transferFrom(address(vault), address(this), profit);

    } else { // assuming if PnL ==0 no changes required just delete /*else if (PnL == 0) {}*/

        uint256 loss = PnL.abs();
        bool success = _liquidateUser(msg.sender, loss);
        if(!success) revert Protocol__RedeemFailed();
    }
    
    }

    //  if user have open position, User can not withdrawal?
    function withdrawCollateral(uint256 _amount) external moreThanZero (_amount) nonReentrant {
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

        function liquidityReservesToHold() external view returns  (uint256 amountToHold){
        // uint256 totalReserve = IERC20(i_acceptedCollateral).balanceOf(address(vault));
        // uint256 totalPositionsSize = longPosition.totalSize + shortPosition.totalSize;
        int256 PnLForLong = _checkPnLForLong(toInt256(longPosition.totalSize), toInt256(longPosition.totalSizeOfToken));
        int256 PnLForShort = _checkPnLForShort(toInt256(shortPosition.totalSize), toInt256(shortPosition.totalSizeOfToken));
        int256 totalPnL = PnLForLong + PnLForShort;
        uint256 amountToKeep = _getAmountToHoldInPool();
        if(totalPnL > 0){
            uint256 profit = totalPnL.abs();
            amountToHold = amountToKeep - profit;
        } else if(totalPnL == 0) {
            amountToHold = amountToKeep;
        } else {
            uint256 loss = totalPnL.abs();
            amountToHold = amountToKeep + loss;
        }

        return amountToHold;
        }




  


    //////////////////////////
    // Internals Functions
    //////////////////////////

    // functions to check reserves to open Positions


    // Function to check PnL
      function _checkProfitOrLossForUser(address user) internal view returns(int256){
        Position memory userCheck = positions[user];
        
        int256 borrowedAmount = toInt256(userCheck.size);
        int256 currValueOfToken = toInt256(_getPriceOfBtc() * userCheck.sizeOfToken);
        int256 PnL;

        // Profit calculate differently
        if(userCheck.isLong) {
            PnL = _checkPnLForLong(borrowedAmount, currValueOfToken);
        } else {
            PnL = _checkPnLForShort(borrowedAmount, currValueOfToken);
        }
        return PnL;
    }


    function _getAmountToHoldInPool() internal view returns(uint256 amountToKeep){
        uint256 totalReserve = IERC20(i_acceptedCollateral).balanceOf(address(vault));
        amountToKeep = (totalReserve/100) * LIQUIDITY_THRESHOLD;
        return amountToKeep;
    }

    // Increase  total positions
      function _increaseTotalLongPosition(uint256 _size, uint256 _numOfToken ) internal {
            longPosition.totalSize += _size;
            longPosition.totalSizeOfToken += _numOfToken;
        }
          function _increaseTotalShortPosition(uint256 _size, uint256 _numOfToken ) internal {
            shortPosition.totalSize += _size;
            shortPosition.totalSizeOfToken += _numOfToken;
        }

        

    /**@dev Liquidate User */
    function _liquidateUser(address user, uint256 lossToCover) internal returns(bool){
         uint256 userBal = s_collateralOfUser[user];
         uint256 amountToCover;
        //  uint256 amountToCover = userBal >= loss ? loss : s_collateralOfUser[user];
         if(userBal >= lossToCover){
            amountToCover = lossToCover;
         } else {
            amountToCover = s_collateralOfUser[user];
         }
            s_collateralOfUser[user] -= amountToCover;
            bool success = _redeemCollateral(address(vault), amountToCover);
            return success;
    }

    // Check Profit or loss of user
        function _checkPnLForLong(int256 size, int256 value) internal pure returns(int256) {
            int256 PnL = value - size;
            return PnL;

        }
         function _checkPnLForShort(int256 size, int256 value) internal pure returns(int256) {
            int256 PnL = size - value;
            return PnL;

        }


    // function transfer(address to, uint256 amount) external returns (bool);

    // function convertToUint(int256 _num) public pure returns (uint256) {
    //     return _num.abs();
    // }

    // To convert the value of uint256 to int256 safely
    function toInt256(uint256 value) internal pure returns (int256) {
        require(value <= uint256(type(int256).max), "Value exceeds int256 max");
        return int256(value);
    }

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
