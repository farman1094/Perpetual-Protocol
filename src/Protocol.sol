// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title PrepProtocol
 * @author Mohd Farman
 * This system is designed to be as minimal as possible.
 * NOTE This system accept PrepToken as a collateral for both Trader and Liquidy Provider.
 * In this system you can open positions for Bitcoin
 */
contract Protocol is ReentrancyGuard {
    // errors
    error Protocol__NeedsMoreThanZero();
    error Protocol__FundsNotAvailableForPosition();
    error Protocol__CurrentlyNumberIsZero();
    error Protocol__TraderCannotLiquidateHimself();

    error Protocol__CannotDecreaseSizeMoreThanPosition();
    error Protocol__RedeemOrFeeTransferFailed();
    error Protocol__PnLNotHandled();
    error Protocol__DepositFailed();
    error Protocol__IdNotExistToCheckLiquidabalePosition();
    error Protocol__LiquidationFailed();
    error Protocol__LeverageLimitReached();
    error Protocol__UserNotHaveEnoughBalance();
    error Protocol__OpenPositionRequired();
    error Protocol__AlreadyUpdated();
    error Protocol__OnlyAdminCanUpdate();
    error Protocol__TokenValueIsMoreThanSize();
    error Protocol__CollateralReserveIsNotAvailable();
    error Protocol__CannotChangeSizeInLoss__FirstSettleTheExistDues();
    error Protocol__UserCanOnlyHaveOnePositionOpened();
    error Protocol__PositionClosingFailed();
    error Protocol__PositionIsNotLiquidable();

    using SignedMath for int256;
    using OracleLib for AggregatorV3Interface;

    struct Position {
        uint256 id; // With Id Arbitary's actor can check if trader is liquidable or not
        uint256 size; // BorrowedMoney
        uint256 sizeOfToken; //Token Purchased from Borrowed Money
        uint256 openAt; // Time when position opened
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
    IVault private vault;
    uint256 private s_numOfOpenPositions;
    uint256[] private s_availableIdsToUse;

    uint256 constant LEVERAGE_RATE = 15e18; // Leverage rate if 10$ can open the position for $150 (18 decimals for precesion)
    uint256 constant LIQUIDABALE_LEVERAGE_RATE = 30e18; // after 30x position is liquidabale
    uint256 constant LIQUIDITY_THRESHOLD = 15; // if total supply is 100, lp's have to keep 15% in the pool any loses (15+lose) (15 - profit)
    uint256 constant LIQUIDATION_REWARD_BASIS = 50; // 50 / 10,000 (0.5%) of liquidable position
    uint256 constant TOTAL_BASIS_POINT_HELPER = 10000; // to get the percentage

    uint256 constant BORROWING_RATE_PER_YEAR = 15; // the interest rate on holding per year
    uint256 constant HELPER_TO_CALCULATE_PERCENTAGE = 100; // To get Percentage Helper
    uint256 constant YEAR_IN_SECONDS = 31536000; //31,536,000 seconds in a year
    uint256 constant PRECISION = 1e18;
    uint256 constant PRICE_PRECISION = 1e10;

    address immutable i_acceptedCollateral;
    address immutable i_ADMIN; // Admin to update Vault Address
    address immutable i_BTC;

    bool private alreadyUpdated = false;

    mapping(address => Position) positions;
    mapping(uint256 => Position) positionsById;
    mapping(address => uint256) s_collateralOfUser;
    mapping(uint256 => address) s_AddressById;
    // address constant token = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43; // Price Feed adress for token/USD

    LongPosition public longPosition;
    ShortPosition public shortPosition;

    // Events
    event CollateralDeposited(address indexed sender, uint256 amount);
    event CollateralWithdrawed(address indexed sender, uint256 amount);
    event PositionUpdated(address indexed sender, uint256 size);
    // event PositionIncreasedBy(address indexed sender, uint256 size);
    // event PositionClose(address indexed user, uint256 size);

    //////////////////////////
    // Modifiers
    //////////////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert Protocol__NeedsMoreThanZero();
        _;
    }

    constructor(address collateralAddress, address _i_ADMIN, address btc) {
        i_acceptedCollateral = collateralAddress;
        i_ADMIN = _i_ADMIN;
        i_BTC = btc;
    }

    //////////////////////////
    // External Functions
    //////////////////////////

    function updateVaultAddress(address _vaultAddress) external {
        if (alreadyUpdated) revert Protocol__AlreadyUpdated();
        if (msg.sender != i_ADMIN) revert Protocol__OnlyAdminCanUpdate();
        vault = IVault(_vaultAddress);
        alreadyUpdated = true;
    }

    //NOTE Prior using this function provide allowance to this contract of PrepToken.
    function depositCollateral(uint256 amount) external moreThanZero(amount) nonReentrant {
        s_collateralOfUser[msg.sender] += amount;
        emit CollateralDeposited(msg.sender, amount);
        bool success = IERC20(i_acceptedCollateral).transferFrom(msg.sender, address(this), amount);
        if (!success) revert Protocol__DepositFailed();
    }

    // Note Any trader can increase the position with the collateral he has, only requeirement is to have the realTime leverage under 15x even with the new size
    function increasePosition(uint256 _size) external moreThanZero(_size) nonReentrant {
        // Position memory UserPosition = positions[msg.sender];
        if (positions[msg.sender].isInitialized == false) {
            revert Protocol__OpenPositionRequired();
        }
        (uint256 leverageRate,) = checkPositionLeverageAndLiquidability(positions[msg.sender].id);
        if (leverageRate >= LEVERAGE_RATE) {
            // checking leverage is under 15 before as well to be so the gas fee will not be wasted
            revert Protocol__LeverageLimitReached();
        }

        bool reservesAvailable = _isCollateralAvailable(_size);
        if (!reservesAvailable) revert Protocol__CollateralReserveIsNotAvailable();

        uint256 borrowingFee = _calculateBorrowFee(positions[msg.sender].size, positions[msg.sender].openAt); // paid fees till now
        _handleAmountDeduction(msg.sender, borrowingFee); // till now borrowing fee taken

        bool eligible = _checkLeverageFactorWhileIncreasing(msg.sender, _size);
        if (!eligible) revert Protocol__LeverageLimitReached();
        uint256 numOfToken = _getNumOfTokenByAmount(_size);
        positions[msg.sender].openAt = block.timestamp;
        positions[msg.sender].size += _size;
        positions[msg.sender].sizeOfToken += numOfToken;
        positionsById[positions[msg.sender].id] = positions[msg.sender];
        emit PositionUpdated(msg.sender, positions[msg.sender].size);
        updateTotalAccountingForAdding(positions[msg.sender].isLong, _size, numOfToken);
    }

    /**
     * NOTE Anyone can decrease the size of position no matter Profit or in loss, until the realTime leverage is under 15x
     */
    function decreasePosition(uint256 sizeToDec) external moreThanZero(sizeToDec) {
        if (positions[msg.sender].isInitialized == false) {
            revert Protocol__OpenPositionRequired();
        }
        if (positions[msg.sender].size <= sizeToDec) {
            revert Protocol__CannotDecreaseSizeMoreThanPosition();
        }

        _decreasePosition(msg.sender, sizeToDec);
    }

    /**
     * NOTE You can open position with collateral at 15% leverage rate
     * @param _size the borrowing amount or position,
     * @param _isLong (send true for long, false for short)
     */
    function openPositionWithSize(uint256 _size, bool _isLong) external moreThanZero(_size) {
        uint256 numOfToken = _getNumOfTokenByAmount(_size);
        openPosition(_size, numOfToken, _isLong);
    }

    /**@param _numOfToken you can open position with token */
     function openPositionWithToken(uint256 _numOfToken, bool _isLong) external moreThanZero(_numOfToken) {
        int256 actualValueOfToken = _getActualValueOfToken(toInt256(_numOfToken));
        uint size = actualValueOfToken.abs();
        openPosition(size, _numOfToken, _isLong);
    }


    // Function to close the position and clear the dues, For both Profit and loss cases.
    function closePosition() external {
        if (positions[msg.sender].isInitialized == false) {
            revert Protocol__OpenPositionRequired();
        }
        _closePosition(msg.sender);
    }

    /**
     * NOTE Any trader can withdraw  ( even in an open Position until It is not affected leverage rate of 15x)
     */
    function withdrawCollateral(uint256 _amount) external moreThanZero(_amount) nonReentrant {
        if (s_collateralOfUser[msg.sender] < _amount) {
            revert Protocol__UserNotHaveEnoughBalance();
        }

        s_collateralOfUser[msg.sender] -= _amount;

        // leverage
        if (positions[msg.sender].isInitialized) {
            uint256 leverageRate = _checkLeverageRateOfPositionHandlingPnL(msg.sender);
            if (leverageRate > LEVERAGE_RATE) {
                revert Protocol__LeverageLimitReached();
            }
        }

        _redeemCollateral(msg.sender, _amount);
        emit CollateralWithdrawed(msg.sender, _amount);
    }

    /**
     * This function is for Vault to prevent liquidity providers to withdraw the collateral which is reserve for Traders
     * It calculates according to total open positions if the all the protocol users is in loss or profit
     * Note Reserve Rate is 15% of total collateral, Additional accounting also keep in mind for flexibility.
     * In the situation of Loss or Profit to Protocol. If Loss (amountToHold + 15%) In Profit (amountToHold - 15%)
     *  it returns @param amountToHold Which needed to hold in Vault for clear traders dues
     */
    function liquidityReservesToHold() external view returns (uint256 amountToHold) {
        return _liquidityReservesToHold();
    }

    /* NOTE
    * this function will liquidate position if position has more than 30x leverage, and reward 0.5% of liquidable position to the liquidator.
    * if Collateral have the money to pay the reward, otherwise it will pay the reward from the collateral 
    * and the remaining amount will be paid by the protocol. because it helps protocol to keep the system stable.
    * In liquidation we will decrease the position to 2/3 of the original size after taking (borrowingFee, PnL and liquidationReward) 
    * rest given to traders.
    * After decreasing if leverage decrease to 15 then good otherwise we will close particular position.
    */
    function liquidatePosition(uint256 _id) public nonReentrant {
        (, bool isLiquidabale) = checkPositionLeverageAndLiquidability(_id);
        if (!isLiquidabale) revert Protocol__PositionIsNotLiquidable();
        address liquidabaleAddr = s_AddressById[_id];
        if (liquidabaleAddr == msg.sender) revert Protocol__TraderCannotLiquidateHimself();
        uint256 reward = _calculateLiquidableReward(positions[liquidabaleAddr].size);
        uint256 sizeToDec = (positions[liquidabaleAddr].size * 2) / 3;
        _decreasePosition(liquidabaleAddr, sizeToDec);
        uint256 remainingBalOfTraderGotLiquidated = s_collateralOfUser[liquidabaleAddr];

        if (remainingBalOfTraderGotLiquidated >= reward) {
            s_collateralOfUser[liquidabaleAddr] -= reward;
            s_collateralOfUser[msg.sender] += reward;
        } else {
            s_collateralOfUser[msg.sender] += reward;
            s_collateralOfUser[liquidabaleAddr] -= remainingBalOfTraderGotLiquidated;
            uint256 remainingReward = reward - remainingBalOfTraderGotLiquidated;
            bool success = IERC20(i_acceptedCollateral).transferFrom(address(vault), address(this), remainingReward);
            require(success, "Liquidation reward Transfer failed");
        }

        uint256 leverageRate = _checkLeverageRateOfPositionHandlingPnL(liquidabaleAddr);
        if (leverageRate > LEVERAGE_RATE) {
            _closePosition(liquidabaleAddr);
        }
    }

    /**
     * It take @param _id to check particular position and it will return :-
     * @param leverageRate - actual leverage rate of position
     * @param isLiquidabale - True if position is liquidable otherwise false
     */
    function checkPositionLeverageAndLiquidability(uint256 _id)
        public
        view
        returns (uint256 leverageRate, bool isLiquidabale)
    {
        address sender = s_AddressById[_id];
        // @note confirm if required
        if (sender == address(0)) {
            revert Protocol__IdNotExistToCheckLiquidabalePosition();
        }
        if (positions[sender].isInitialized == false) {
            //confirm if really required
            revert Protocol__OpenPositionRequired();
        }
        leverageRate = _checkLeverageRateOfPositionHandlingPnL(sender);
        isLiquidabale = leverageRate >= LIQUIDABALE_LEVERAGE_RATE ? true : false;
        return (leverageRate, isLiquidabale);
    }

    //////////////////////////
    // Internals Functions
    //////////////////////////

        // function to get Open Position
        function openPosition(uint256 _size,uint256 numOfToken, bool _isLong) internal {
        if (positions[msg.sender].isInitialized) {
            revert Protocol__UserCanOnlyHaveOnePositionOpened();
        }
        bool reservesAvailable = _isCollateralAvailable(_size);
        if (!reservesAvailable) revert Protocol__CollateralReserveIsNotAvailable();

        bool eligible = _checkLeverageFactorWhileIncreasing(msg.sender, _size);
        if (!eligible) revert Protocol__LeverageLimitReached();

        s_numOfOpenPositions++;
        uint256 _id;

        if (s_availableIdsToUse.length > 0) {
            _id = s_availableIdsToUse[s_availableIdsToUse.length - 1];
            s_availableIdsToUse.pop();
        } else {
            _id = s_numOfOpenPositions;
        }

        positions[msg.sender] = Position({
            id: _id,
            size: _size,
            sizeOfToken: numOfToken,
            openAt: block.timestamp,
            isLong: _isLong,
            isInitialized: true
        });
        positionsById[_id] = positions[msg.sender];
        s_AddressById[_id] = msg.sender;
        emit PositionUpdated(msg.sender, _size);

        // get the total of short or long;
        updateTotalAccountingForAdding(_isLong, _size, numOfToken);
    }

    // Explained in funciton liquidityReservesToHold
    function _liquidityReservesToHold() internal view returns (uint256 amountToHold) {
        uint256 totalReserve = IERC20(i_acceptedCollateral).balanceOf(address(vault));
        if (totalReserve == 0) revert Protocol__CollateralReserveIsNotAvailable();
        int256 PnLForLongForUser =
            _checkPnLForLong(toInt256(longPosition.totalSize), toInt256(longPosition.totalSizeOfToken));
        int256 PnLForShortUser =
            _checkPnLForShort(toInt256(shortPosition.totalSize), toInt256(shortPosition.totalSizeOfToken));

        uint256 totalOpenPosition;
        uint256 amountToKeep;
        if (longPosition.totalSize > shortPosition.totalSize) {
            totalOpenPosition = longPosition.totalSize - shortPosition.totalSize;
        } else {
            totalOpenPosition = shortPosition.totalSize - longPosition.totalSize;
        }

        if (totalOpenPosition == 0) {
            amountToKeep = 0;
        } else {
            amountToKeep = _getTheresholdOfReserve(totalOpenPosition);
        }

        int256 totalPnLForUser = PnLForLongForUser + PnLForShortUser;

        if (totalPnLForUser > 0) {
            amountToHold = amountToKeep + totalPnLForUser.abs();
        } else if (totalPnLForUser == 0) {
            amountToHold = amountToKeep;
        } else {
            uint256 profitToLps = totalPnLForUser.abs();
            amountToHold = profitToLps >= amountToKeep ? 0 : amountToKeep - profitToLps;
        }
        return amountToHold;
    }

    // function to Check if reserves available
    function _isCollateralAvailable(uint256 _size) internal view returns (bool reservesAvailable) {
        uint256 portionOfSize = _getTheresholdOfReserve(_size);
        uint256 amountShoulExistInPool = _liquidityReservesToHold();

        uint256 totalReserve = IERC20(i_acceptedCollateral).balanceOf(address(vault));
        reservesAvailable = totalReserve < (portionOfSize + amountShoulExistInPool) ? false : true;
    }

    // function to get Real Time collateral of trader Taking care of Profit or Loss
    function _getCurrentCollateralOfUser(address sender) internal view returns (uint256) {
        uint256 userColl = s_collateralOfUser[sender];
        int256 PnL = _checkProfitOrLossForUser(sender);
        int256 currCollateralOfUser;
        if (PnL < 0) {
            if (PnL.abs() >= userColl) {
                currCollateralOfUser = 1e18; // 0 is undefined by divide so 1
            } else {
                currCollateralOfUser = toInt256(userColl) + PnL;
            }
        } else {
            currCollateralOfUser = toInt256(userColl) + PnL;
        }
        return currCollateralOfUser.abs();
    }

    /**
     * Helper internal function for closing function to use it twice / In closing and liquidate
     * It will delete all the existing mapping for existing trader,
     * and it will push the id to array s_availableIdsToUse to use that id again
     * Handle borrowing Fee and PnL
     */
    function _closePosition(address traderToClose) internal {
        Position memory userToClose = positions[traderToClose];

        int256 PnL = _checkProfitOrLossForUser(traderToClose);

        // Handle and deduct borrowing fee
        uint256 borrowingFee = _calculateBorrowFee(userToClose.size, userToClose.openAt);
        _handleAmountDeduction(traderToClose, borrowingFee);

        // reset the mapping
        delete positions[traderToClose]; //confirm the position
        delete positionsById[userToClose.id];
        delete s_AddressById[userToClose.id];
        emit PositionUpdated(traderToClose, positions[traderToClose].size);

        // s_numOfOpenPositions--; it would not happen becuase we save the deleted it to use it on the new one
        s_availableIdsToUse.push(userToClose.id);

        // handle Profit and loss
        bool requireSuccess = _handleProfitAndLoss(PnL, traderToClose);
        if (!requireSuccess) revert Protocol__PnLNotHandled();

        // Update the total Accounting
        updateTotalAccountingForDecreasing(userToClose.isLong, userToClose.size, userToClose.sizeOfToken);
    }

    /**
     * NOTE internal function of handling the decreasing,
     * @param sizeToDec it is the size to be decreased from current position. New Position = (position - sizeToDec)
     * It will take the borrowing fee till now, and distribute the portion of ProfitOrLoss according to the size which is decreasing.
     */
    function _decreasePosition(address traderToDec, uint256 sizeToDec) internal {
        Position memory userToDec = positions[traderToDec];

        uint256 priceOfPurchase = _getPriceOfPurchase(traderToDec);
        uint256 remainingSize = userToDec.size - sizeToDec;
        uint256 numOfRemainingToken = (remainingSize * PRECISION) / priceOfPurchase;

        //send amount to vault pending
        uint256 borrowingFee = _calculateBorrowFee(userToDec.size, userToDec.openAt); // paid fees till now

        // s_collateralOfUser[traderToDec] -= borrowingFee; // we have taken a borrowing fee till now
        _handleAmountDeduction(traderToDec, borrowingFee);

        // need to handle PnL here
        bool requireSuccess = _handleProfitAndLossWhileDecreasing(sizeToDec, traderToDec);
        if (!requireSuccess) revert Protocol__PnLNotHandled();

        // update accounting
        positions[traderToDec].size = remainingSize;
        positions[traderToDec].sizeOfToken = numOfRemainingToken;
        positions[traderToDec].openAt = block.timestamp; // time reset according to new size (old size till now fees taken)
        positionsById[userToDec.id] = positions[traderToDec];
        emit PositionUpdated(traderToDec, positions[traderToDec].size);
        updateTotalAccountingForDecreasing(userToDec.isLong, sizeToDec, (userToDec.sizeOfToken - numOfRemainingToken));
    }

    // function to calcualate liquidate rewards 0.5 of size
    function _calculateLiquidableReward(uint256 size) internal pure returns (uint256) {
        return (size * LIQUIDATION_REWARD_BASIS) / TOTAL_BASIS_POINT_HELPER;
    }

    /**
     * Check position if liquidable by address by real time collateral
     * it return param leverage with 18 decimals to achieve precision
     * Size / (collateral + ProfitOrLoss)
     */
    function _checkLeverageRateOfPositionHandlingPnL(address sender) internal view returns (uint256) {
        Position memory trader = positions[sender];
        uint256 currCollateralOfUser = _getCurrentCollateralOfUser(sender);
        uint256 leverage = (trader.size * PRECISION) / currCollateralOfUser;
        return leverage;
    }

    // Function to handle profit and loss carefully In the scenarios where loss > collateral
    function _handleProfitAndLoss(int256 PnL, address sender) internal returns (bool) {
        if (PnL > 0) {
            uint256 profit = PnL.abs(); // convert int to uint256
            s_collateralOfUser[sender] += profit;
            bool success = IERC20(i_acceptedCollateral).transferFrom(address(vault), address(this), profit);
            require(success, "Profit Transfer failed");
        } else if (PnL < 0) {
            uint256 loss = PnL.abs();
            _handleAmountDeduction(sender, loss);
        }
        return true;
    }

    // Function to get the profit or loss according to the portion is decreasing
    function _handleProfitAndLossWhileDecreasing(uint256 _sizeToDec, address _sender) internal returns (bool) {
        int256 PnL = _checkProfitOrLossForUser(_sender);
        int256 PnLtoCover = PnL * toInt256(_sizeToDec) / toInt256(positions[_sender].size);
        return _handleProfitAndLoss(PnLtoCover, _sender);
    }

    // function get Price of purchase
    function _getPriceOfPurchase(address sender) public view returns (uint256 price) {
        price = (positions[sender].size * PRECISION) / positions[sender].sizeOfToken;
        return price;
    }

    // Calculate borrowing fee rate is 15% of openSize per year
    function _calculateBorrowFee(uint256 size, uint256 openAt) internal view returns (uint256 borrowingFee) {
        uint256 timePassed = block.timestamp - openAt;
        uint256 holdAmount = (size * LIQUIDITY_THRESHOLD) / HELPER_TO_CALCULATE_PERCENTAGE;
        uint256 rate = (BORROWING_RATE_PER_YEAR * PRECISION) / (HELPER_TO_CALCULATE_PERCENTAGE * YEAR_IN_SECONDS); // (15 / 100  * 1e18(divide later)) * (1 * 31536000)
        borrowingFee = (rate * timePassed * holdAmount) / PRECISION;
        return borrowingFee;
    }

    /**
     * function to get the profit or loss of  user
     */
    function _checkProfitOrLossForUser(address user) internal view returns (int256) {
        Position memory userCheck = positions[user];

        int256 borrowedAmount = toInt256(userCheck.size);
        int256 token = toInt256(userCheck.sizeOfToken);
        int256 PnL;

        if (userCheck.isLong) {
            PnL = _checkPnLForLong(borrowedAmount, token);
        } else {
            PnL = _checkPnLForShort(borrowedAmount, token);
        }
        return PnL;
    }

    // Return 15% of totalSupply of Reserves
    function _getTheresholdOfReserve(uint256 resereves) internal pure returns (uint256 amountToKeep) {
        // uint256 totalReserve = IERC20(i_acceptedCollateral).balanceOf(address(vault));

        amountToKeep = (resereves * LIQUIDITY_THRESHOLD) / HELPER_TO_CALCULATE_PERCENTAGE;
        return amountToKeep;
    }

    // These functions used for the accounting for total open positions
    function updateTotalAccountingForAdding(bool isLong, uint256 _size, uint256 _numOfToken) internal {
        if (isLong) {
            longPosition.totalSize += _size;
            longPosition.totalSizeOfToken += _numOfToken;
        } else {
            shortPosition.totalSize += _size;
            shortPosition.totalSizeOfToken += _numOfToken;
        }
    }

    function updateTotalAccountingForDecreasing(bool isLong, uint256 _size, uint256 _numOfToken) internal {
        if (isLong) {
            longPosition.totalSize -= _size;
            longPosition.totalSizeOfToken -= _numOfToken;
        } else {
            shortPosition.totalSize -= _size;
            shortPosition.totalSizeOfToken -= _numOfToken;
        }
    }

    // function to get actual value of token (token * price) = valueOfToken
    function _getActualValueOfToken(int256 _sizeOfToken) public view returns (int256 actuaTokenValue) {
        actuaTokenValue = toInt256((_getPriceOfBtc() * _sizeOfToken.abs()) / PRECISION);
        return actuaTokenValue;
    }

    // function to handle the deduction carefully
    function _handleAmountDeduction(address user, uint256 lossToCover) internal {
        if (lossToCover == 0) {
            return;
        }
        uint256 userBal = s_collateralOfUser[user];
        uint256 amountToCover = userBal >= lossToCover ? lossToCover : s_collateralOfUser[user];
        s_collateralOfUser[user] -= amountToCover;
        _redeemCollateral(address(vault), amountToCover);
    }

    // Check Profit or loss according to the type of position
    function _checkPnLForLong(int256 size, int256 token) internal view returns (int256) {
        int256 actualValue = _getActualValueOfToken(token); // toInt256( * _getPriceOfBtc());
        int256 PnL = actualValue - size;
        return PnL;
    }

    function _checkPnLForShort(int256 size, int256 token) internal view returns (int256) {
        int256 actualValue = _getActualValueOfToken(token); // toInt256( * _getPriceOfBtc());
        int256 PnL = size - actualValue;
        return PnL;
    }

    // To convert the value of uint256 to int256 safely
    function toInt256(uint256 value) internal pure returns (int256) {
        require(value <= uint256(type(int256).max), "Value exceeds int256 max");
        return int256(value);
    }

    // Amount transfers to vault (fees) or traders (reddeming collateral / Profit)
    function _redeemCollateral(address receiver, uint256 amount) internal {
        bool success = IERC20(i_acceptedCollateral).transfer(receiver, amount);
        if (!success) revert Protocol__RedeemOrFeeTransferFailed();
    }

    // check leverage for new user without the checking the profit or losses
    function _checkLeverageFactorWhileIncreasing(address sender, uint256 _size) internal view returns (bool) {
        if (positions[sender].isInitialized) {
            return _checkLeverageFactorWhileIncreasingForExisting(sender, _size);
        } else {
            return _checkLeverageFactorWhileIncreasingForNew(sender, _size);
        }
    }

    // to check leverage percentage for new users as per approved
    function _checkLeverageFactorWhileIncreasingForNew(address sender, uint256 _size) internal view returns (bool) {
        uint256 collateralOfUser = s_collateralOfUser[sender];
        if (collateralOfUser == 0) {
            return false;
        }
        uint256 sizeLimit = (collateralOfUser * LEVERAGE_RATE) / PRECISION;
        if (sizeLimit >= _size) {
            return true;
        } else {
            return false;
        }
    }

    // to check leverage percentage for existing user is as per approved
    function _checkLeverageFactorWhileIncreasingForExisting(address sender, uint256 _size)
        internal
        view
        returns (bool eligible)
    {
        uint256 currCollateralOfUser = _getCurrentCollateralOfUser(sender);
        uint256 sizeLimit = (currCollateralOfUser * LEVERAGE_RATE) / PRECISION;
        uint256 sizeAskingFor = _size + positions[sender].size;
        eligible = sizeLimit < sizeAskingFor ? false : true;
    }

    // According to size how much token get // (size should be in 1e18)
    function _getNumOfTokenByAmount(uint256 amount) internal view returns (uint256) {
        uint256 priceOfBtc = _getPriceOfBtc();
        uint256 numOfToken = (amount * PRECISION) / priceOfBtc;
        return numOfToken;
    }

    function _getPriceOfBtc() internal view returns (uint256 price) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(i_BTC);
        (, int256 answer,,,) = priceFeed.staleCheckLatestRoundData(); // Lib use
        return uint256(answer) * PRICE_PRECISION; //Making it (Price)e18
    }

    //////////////////////////
    // Getters and View function
    //////////////////////////

    // Get the ids which are not in use
    // You can use id's `s_numOfOpenPositions` excluding this id's
    function getIdsNotInUse() public view returns (uint256[] memory) {
        return s_availableIdsToUse;
    }

    //  If users doesn't have open position it will return 0
    function checkProfitOrLossForUser(address _user) public view returns (int256 PnL) {
        Position memory userToClose = positions[_user];
        if (userToClose.isInitialized == false) {
            // revert Protocol__OpenPositionFirst(); // View function should not revert
            PnL = 0;
        } else {
            PnL = _checkProfitOrLossForUser(_user);
        }
        return PnL;
    }

    // Get total open positions accounting
    function getTotalLongPositions() public view returns (uint256 totalSize, uint256 totalSizeOfToken) {
        totalSize = longPosition.totalSize;
        totalSizeOfToken = longPosition.totalSizeOfToken;
        return (totalSize, totalSizeOfToken);
    }

    function getTotalShortPositions() public view returns (uint256 totalSize, uint256 totalSizeOfToken) {
        totalSize = shortPosition.totalSize;
        totalSizeOfToken = shortPosition.totalSizeOfToken;
        return (totalSize, totalSizeOfToken);
    }

    // If user does not exist it will return ( 0, 0,0,0, false, false)
    function getPositionDetails(address user)
        public
        view
        returns (uint256 id, uint256 size, uint256 sizeOfToken, uint256 openAt, bool isLong, bool isInitialized)
    {
        id = positions[user].id;
        size = positions[user].size;
        sizeOfToken = positions[user].sizeOfToken;
        openAt = positions[user].openAt;
        isLong = positions[user].isLong;
        isInitialized = positions[user].isInitialized;
        return (id, size, sizeOfToken, openAt, isLong, isInitialized);
    }

    // Get number of Open Positions
    function getNumOfOpenPositions() public view returns (uint256) {
        return s_numOfOpenPositions;
    }

    // Get Collateral balance of user
    function getCollateralBalance() public view returns (uint256) {
        return s_collateralOfUser[msg.sender];
    }

    // Get vault address
    function getVaultAddress() public view returns (address) {
        return address(vault);
    }
    // Get collateral address

    function getCollateralAddress() public view returns (address) {
        return i_acceptedCollateral;
    }

    // Get price of BTC real Time
    function getPriceOfBtc() public view returns (uint256 price) {
        return _getPriceOfBtc();
    }

    // Get num of token you get in provided amount
    function getNumOfTokenByAmount(uint256 amount) public view returns (uint256) {
        return _getNumOfTokenByAmount(amount);
    }

    // Check your size limit if it can be approved (If already deposited)
    function checkLeverageFactorWhileIncreasing(address sender, uint256 _size) public view returns (bool) {
        return _checkLeverageFactorWhileIncreasing(sender, _size);
    }

    // // Calculate the borrowing fee for test
    function getIdByAddress(address sender) public view returns (uint256 id) {
        if (positions[sender].isInitialized == false) {
            return 0;
        }
        return positions[sender].id;
    }

    // function to get the price of purchase by address
    function getPriceOfPurchaseByAddress(address sender) public view returns (uint256 price) {
        return _getPriceOfPurchase(sender);
    }
}
