// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Vault} from "src/Vault.sol";

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

    error Protocol__DepositFailed();
    error Protocol__RedeemFailed();
    error Protocol__LiquidationFailed();
    error Protocol__LeverageLimitReached();
    error Protocol__UserNotEnoughBalance();
    error Protocol__CannotWithdrawWithOpenPosition();
    error Protocol__OpenPositionFirst();
    error Protocol__AlreadyUpdated();
    error Protocol__OnlyAdminCanUpdate();
    error Protocol__TokenValueIsMoreThanSize();
    error Protocol__CollateralReserveIsNotAvailable();
    error Protocol__CannotIncreaseSizeInLoss__FirstSettleTheExistDues();
    error Protocol__PositionAlreadyOpened();

    using SignedMath for int256;

    struct Position {
        uint256 size; // BorrowedMoney
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

    uint256 constant LEVERAGE_RATE = 15; // Leverage rate if 10$ can open the position for $150
    uint256 constant LIQUIDITY_THRESHOLD = 15; // if total supply is 100, lp's have to keep 15% in the pool any loses (15+lose) (15 - profit)

    uint256 constant PRICE_PRECISION = 1e10;
    uint256 constant PRECISION = 1e18;

    address immutable i_acceptedCollateral;
    address immutable i_ADMIN; // Admin to update Vault Address
    address immutable i_BTC;

    bool private alreadyUpdated = false;

    mapping(address => Position) positions;
    mapping(address => uint256) s_collateralOfUser;
    uint256 private s_numOfOpenPositions;
    // address constant token = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43; // Price Feed adress for token/USD

    LongPosition public longPosition;
    ShortPosition public shortPosition;

    // Events
    event CollateralDeposited(address indexed sender, uint256 amount);
    event PositionOpened(address indexed sender, uint256 size);
    event PositionClose(address indexed user, uint256 size);

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
        vault = Vault(_vaultAddress);
        alreadyUpdated = true;
    }

    //NOTE Prior using this function provide allowance to this contract of PrepToken.
    function depositCollateral(uint256 amount) external moreThanZero(amount) nonReentrant {
        s_collateralOfUser[msg.sender] += amount;
        emit CollateralDeposited(msg.sender, amount);
        bool success = IERC20(i_acceptedCollateral).transferFrom(msg.sender, address(this), amount);
        if (!success) revert Protocol__DepositFailed();
    }

    // Note only Open position size can be increased and traders in loss cannot increase positions
    function increasePosition(uint256 _size) external moreThanZero(_size) {
        // Position memory UserPosition = positions[msg.sender];
        if (positions[msg.sender].isInitialized == false) {
            revert Protocol__OpenPositionFirst();
        }
        int256 PnL = _checkProfitOrLossForUser(msg.sender);
        if (PnL < 0) revert Protocol__CannotIncreaseSizeInLoss__FirstSettleTheExistDues();
        bool eligible = checkLeverageFactor(msg.sender, _size);
        if (!eligible) revert Protocol__LeverageLimitReached();
        uint256 numOfToken = _getNumOfTokenByAmount(_size);
        positions[msg.sender].size += _size;
        positions[msg.sender].sizeOfToken += numOfToken;

        updateTotalAccounting(positions[msg.sender].isLong, _size, numOfToken);
    }

    /**
     * NOTE You can open position with collateral at 15% leverage rate
     * @param _size the borrowing amount or position, @param _sizeOfToken the number of token you want to trade it take in 1e18
     * @param _isLong (send true for long, false for short)
     */
    function openPosition(uint256 _size, uint256 _sizeOfToken, bool _isLong) external moreThanZero(_size) {
        if(positions[msg.sender].isInitialized) {
            revert Protocol__PositionAlreadyOpened();
        }
        uint256 totalReserve = IERC20(i_acceptedCollateral).balanceOf(address(vault));
        if (totalReserve == 0) revert Protocol__CollateralReserveIsNotAvailable();

        bool eligible = checkLeverageFactor(msg.sender, _size);
        if (!eligible) revert Protocol__LeverageLimitReached();
        uint256 numOfToken;

        if (_sizeOfToken == 0) {
            numOfToken = _getNumOfTokenByAmount(_size);
        } else {
            uint256 valueofToken = (_sizeOfToken * _getPriceOfBtc())/ PRECISION;
            if (_size < valueofToken) revert Protocol__TokenValueIsMoreThanSize();
            numOfToken = _sizeOfToken;
        }

        if (_isLong) {
            // position for long
            positions[msg.sender] = Position({size: _size, sizeOfToken: numOfToken, isLong: true, isInitialized: true});
        } else {
            //position for short
            positions[msg.sender] = Position({size: _size, sizeOfToken: numOfToken, isLong: false, isInitialized: true});
        }
        emit PositionOpened(msg.sender, _size);

        // get the total of short or long;
        updateTotalAccounting(_isLong, _size, numOfToken);
        s_numOfOpenPositions++;
    }

    // Function to close the position and clear the dues, For both Profit and loss cases.

    function closePosition() external {
        Position memory userToClose = positions[msg.sender];
        if (userToClose.isInitialized == false) {
            revert Protocol__OpenPositionFirst();
        }

        int256 PnL = _checkProfitOrLossForUser(msg.sender);
        // Update the total Accounting
        if (userToClose.isLong) {
            longPosition.totalSize -= userToClose.size;
            longPosition.totalSizeOfToken -= userToClose.sizeOfToken;
        } else {
            shortPosition.totalSize -= userToClose.size;
            shortPosition.totalSizeOfToken -= userToClose.sizeOfToken;
        }

        // reset the mapping
        delete positions[msg.sender]; //confirm the position
        s_numOfOpenPositions--;
        emit PositionClose(msg.sender, userToClose.size);

        if (PnL > 0) {
            uint256 profit = PnL.abs(); // convert int to uint256
            s_collateralOfUser[msg.sender] += profit;
            IERC20(i_acceptedCollateral).transferFrom(address(vault), address(this), profit);
        } else if (PnL < 0) {
            uint256 loss = PnL.abs();
            bool success = _liquidateUser(msg.sender, loss);
            if (!success) revert Protocol__RedeemFailed();
        }
    }

    /**
     * NOTE In order to withdraw money, there should not be any open position
     *     If open position exist it needed to be close first
     */
    function withdrawCollateral(uint256 _amount) external moreThanZero(_amount) nonReentrant {
        Position memory UserPosition = positions[msg.sender];
        if (UserPosition.isInitialized) {
            if (UserPosition.size != 0) {
                revert Protocol__CannotWithdrawWithOpenPosition();
            }
        }

        if (s_collateralOfUser[msg.sender] < _amount) {
            revert Protocol__UserNotEnoughBalance();
        }

        s_collateralOfUser[msg.sender] -= _amount;

        bool success = _redeemCollateral(msg.sender, _amount);
        if (!success) revert Protocol__RedeemFailed();
    }

    /**
     * This function is for Vault to prevent liquidity providers to withdraw the collateral which is reserve for Traders
     * It calculates according to total open positions if the all the protocol users is in loss or profit
     * Note Reserve Rate is 15% of total collateral, Additional accounting also keep in mind for flexibility.
     * In the situation of Loss or Profit to Protocol. If Loss (amountToHold + 15%) In Profit (amountToHold - 15%)
     *  it returns @param amountToHold Which needed to hold in Vault for clear traders dues
     */
    function liquidityReservesToHold() external view returns (uint256 amountToHold) {
        uint256 totalReserve = IERC20(i_acceptedCollateral).balanceOf(address(vault));
        if (totalReserve == 0) revert Protocol__CurrentlyNumberIsZero();
        int256 PnLForLongForUser =
            _checkPnLForLong(toInt256(longPosition.totalSize), toInt256(longPosition.totalSizeOfToken));

        int256 PnLForShortUser =
            _checkPnLForShort(toInt256(shortPosition.totalSize), toInt256(shortPosition.totalSizeOfToken));

        int256 totalPnLForUser = PnLForLongForUser + PnLForShortUser;

        uint256 amountToKeep = _getAmountToHoldInPool();
        if (totalPnLForUser > 0) {
            uint256 lossToLPs = totalPnLForUser.abs();
            amountToHold = amountToKeep + lossToLPs;
        } else if (totalPnLForUser == 0) {
            amountToHold = amountToKeep;
        } else {
            uint256 profitToLps = totalPnLForUser.abs();
            // if(profitToLps >= amountToKeep) {
            //     amountToHold = 0;
            // } else {
            // amountToHold = amountToKeep - profitToLps;
            // }
            amountToHold = profitToLps >= amountToKeep ? 0 : amountToKeep - profitToLps;
        }
        return amountToHold;
    }

    //////////////////////////
    // Internals Functions
    //////////////////////////

    /**
     * @dev Internal fucntion must not be called from outside. Getter function available to use these.
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
    function _getAmountToHoldInPool() internal view returns (uint256 amountToKeep) {
        uint256 totalReserve = IERC20(i_acceptedCollateral).balanceOf(address(vault));
        amountToKeep = (totalReserve / 100) * LIQUIDITY_THRESHOLD;
        return amountToKeep;
    }

    // These functions used for the accounting for total open positions
    function updateTotalAccounting(bool isLong, uint256 _size, uint256 _numOfToken) internal {
        if(isLong){
        longPosition.totalSize += _size;
        longPosition.totalSizeOfToken += _numOfToken;
        } else {
        shortPosition.totalSize += _size;
        shortPosition.totalSizeOfToken += _numOfToken;
        }
    }

    // function _increaseTotalShortPosition(uint256 _size, uint256 _numOfToken) internal {}

    // It return the Actutal value of token by number of token. (sizeOfToken * curentPrice)
    function _getActualValueOfToken(int256 _sizeOfToken) internal view returns (int256 actuaTokenValue) {
        actuaTokenValue = toInt256((_getPriceOfBtc() * _sizeOfToken.abs()) / 1e18);
        return actuaTokenValue;
    }

    /**
     * @dev This function is called is used in situation of losses, When trader come to close position
     */
    function _liquidateUser(address user, uint256 lossToCover) internal returns (bool) {
        uint256 userBal = s_collateralOfUser[user];
        uint256 amountToCover;
        //  uint256 amountToCover = userBal >= loss ? loss : s_collateralOfUser[user];
        if (userBal >= lossToCover) {
            amountToCover = lossToCover;
        } else {
            amountToCover = s_collateralOfUser[user];
        }
        s_collateralOfUser[user] -= amountToCover;
        bool success = _redeemCollateral(address(vault), amountToCover);
        return success;
    }

    // Check Profit or loss of user

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

    // Redeem
    function _redeemCollateral(address receiver, uint256 amount) internal returns (bool success) {
        //         s_collateralOfUser[receiver] -= amount;
        success = IERC20(i_acceptedCollateral).transfer(receiver, amount);
        return success;
    }

    // to check leverage percentage for new users as per approved
    function _checkLeverageFactorForNew(address sender, uint256 _size) internal view returns (bool) {
        uint256 collateralOfUser = s_collateralOfUser[sender];
        if (collateralOfUser == 0) {
            return false;
        }
        uint256 sizeLimit = collateralOfUser * LEVERAGE_RATE;
        if (sizeLimit >= _size) {
            return true;
        } else {
            return false;
        }
    }

    // to check leverage percentage for existing user is as per approved
    function _checkLeverageFactorForExisting(address sender, uint256 _size) internal view returns (bool) {
        Position memory UserPosition = positions[sender];
        uint256 collateralOfUser = s_collateralOfUser[sender];
        uint256 sizeLimit = collateralOfUser * LEVERAGE_RATE;
        uint256 sizeAskingFor = _size + UserPosition.size;
        if (sizeLimit >= sizeAskingFor) {
            return true;
        } else {
            return false;
        }
    }

    // According to size how much token get // (size should be in 1e18)
    function _getNumOfTokenByAmount(uint256 amount) internal view returns (uint256) {
        uint256 priceOfBtc = _getPriceOfBtc();
        uint256 numOfToken = (amount * PRECISION) / priceOfBtc;
        return numOfToken;
    }

    function _getPriceOfBtc() internal view returns (uint256 price) {
        (, int256 answer,,,) = AggregatorV3Interface(i_BTC).latestRoundData();
        price = uint256(answer); // price return amount with e8 (correcting it)
        return price * PRICE_PRECISION;
    }

    //////////////////////////
    // Getters and View function
    //////////////////////////

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

    // If user does not exist it will return ( 0, 0, false, false)
    function getPositionDetails(address user)
        public
        view
        returns (uint256 size, uint256 sizeOfToken, bool isLong, bool isInitialized)
    {
        size = positions[user].size;
        sizeOfToken = positions[user].sizeOfToken;
        isLong = positions[user].isLong;
        isInitialized = positions[user].isInitialized;
        return (size, sizeOfToken, isLong, isInitialized);
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
    function checkLeverageFactor(address sender, uint256 _size) public view returns (bool) {
        if (positions[sender].isInitialized) {
            return _checkLeverageFactorForExisting(sender, _size);
        } else {
            return _checkLeverageFactorForNew(sender, _size);
        }
    }
}
