// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Protocol} from "src/Protocol.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vault} from "src/Vault.sol";
import {PrepToken} from "src/PrepToken.sol";

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";

contract ProtocolTest is Test {
    uint256 constant LEVERAGE_LIMIT = 15e18;

    Protocol protocol;
    PrepToken token;
    Vault vault;
    MockPriceFeed feed;
    address user = makeAddr("user");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    address user4 = makeAddr("user4");
    address user5 = makeAddr("user5");

    function setUp() public {
        vm.startBroadcast(msg.sender);
        feed = new MockPriceFeed();
        token = new PrepToken();
        protocol = new Protocol(address(token), msg.sender, address(feed));
        vault = new Vault(address(token), protocol);
        protocol.updateVaultAddress(address(vault));
        vm.stopBroadcast();
    }

    function testliquidityReservesToHoldwithoutAnyOpenPositionAndLiquidity() public {
        giveLiquidity(); // 10,000
        giveLiquidity();
        vm.startPrank(msg.sender);
        token.mint();

        token.approve(address(protocol), 6000 ether);
        protocol.depositCollateral(6000 ether);
        protocol.openPositionWithSize(60000 ether, false);
        vm.stopPrank();

        console.log("2nd open position--------------");
        vm.startPrank(user);
        token.mint();
        token.approve(address(protocol), 6000 ether);
        protocol.depositCollateral(6000 ether);
        protocol.openPositionWithSize(65000 ether, true);
        // vm.expectRevert(Protocol.Protocol__CollateralReserveIsNotAvailable.selector);
        console.log("loss happen here------------------------");
        feed.updateAnswer(59000e8);
        // total open = 65000 - 60,000 = 5000 * 15% = 750 - traders loss (83$) which is profit to CX so subtracted from 750
        protocol.increasePosition(2 ether); //   amount Needed 666966666666666647000/1e18 => 667 approx
        uint256 amountNeeded = protocol.liquidityReservesToHold();
        assert(amountNeeded < 667 ether);
        vm.stopPrank();
    }

    function testIdsWokingFineAndPricePurchase() public {
        giveLiquidity();
        giveLiquidity();
        vm.startPrank(msg.sender);
        token.mint();

        token.approve(address(protocol), 6000 ether);
        protocol.depositCollateral(6000 ether);
        protocol.openPositionWithSize(60000 ether, true);
        (uint256 id,,,,,) = protocol.getPositionDetails(msg.sender);
        console.log(id);
        vm.stopPrank();

        vm.startPrank(user);
        token.mint();
        token.approve(address(protocol), 6000 ether);
        protocol.depositCollateral(6000 ether);
        protocol.openPositionWithSize(60000 ether, true);
        (uint256 idOfUser,,,,,) = protocol.getPositionDetails(user);
        vm.stopPrank();

        vm.startPrank(user);
        protocol.closePosition();
        vm.stopPrank();

        uint256[] memory idsNotInUse = protocol.getIdsNotInUse();
        assert(idsNotInUse[0] == idOfUser);

        vm.startPrank(user2);
        token.mint();
        token.approve(address(protocol), 6000 ether);
        protocol.depositCollateral(6000 ether);
        protocol.openPositionWithSize(60000 ether, true);
        (uint256 idOfUser2,,,,,) = protocol.getPositionDetails(user2);
        uint256 priceOfPurchase = protocol.getPriceOfPurchaseByAddress(user2);
        uint256 priceOfToken = protocol.getPriceOfBtc();
        vm.stopPrank();

        assert(priceOfPurchase == priceOfToken);
        assert(idOfUser2 == idOfUser);
    }

    function testDecreasePositionIfBorrowigFeeHandledProperly() public {
        giveLiquidity();
        vm.startPrank(msg.sender);
        token.mint();

        token.approve(address(protocol), 6000 ether);
        protocol.depositCollateral(6000 ether);
        protocol.openPositionWithSize(60000 ether, true);
        vm.warp(block.timestamp + 31536000);
        protocol.decreasePosition(4000 ether);
        protocol.decreasePosition(4000 ether);
        (,,, uint256 openAt,,) = protocol.getPositionDetails(msg.sender);
        console.log(openAt);
    }

    function testIncreasePositionIfBorrowigFeeHandledProperly() public {
        giveLiquidity();
        vm.startPrank(msg.sender);
        token.mint();

        token.approve(address(protocol), 6000 ether);
        protocol.depositCollateral(6000 ether);
        protocol.openPositionWithSize(60000 ether, true);
        vm.warp(block.timestamp + 31536000);
        protocol.increasePosition(4000 ether);
        protocol.increasePosition(4000 ether);
        protocol.increasePosition(1000 ether);

        (, uint256 size,, uint256 openAt,,) = protocol.getPositionDetails(msg.sender);
        console.log("collateral of User", protocol.getCollateralBalance());
        console.log("size of User", size);
        console.log(openAt);
        vm.expectRevert(Protocol.Protocol__LeverageLimitReached.selector);
        protocol.increasePosition(1000 ether);
    }

    function testWithdrawalWithOpenPosition() public {
        giveLiquidity();
        vm.startPrank(msg.sender);
        token.mint();

        token.approve(address(protocol), 6000 ether);
        protocol.depositCollateral(6000 ether);
        protocol.openPositionWithSize(60000 ether, true);
        feed.updateAnswer(59000e8);
        // collateral 4000 (1000 loss)
        uint256 userCollateralBeforeWith = protocol.getCollateralBalance();
        protocol.withdrawCollateral(1000 ether);
        uint256 userCollateralAfterWith = protocol.getCollateralBalance();
        assert((userCollateralBeforeWith - 1000e18) == userCollateralAfterWith);

        vm.expectRevert(Protocol.Protocol__LeverageLimitReached.selector);
        protocol.withdrawCollateral(1 ether);
    }

    function testClosingPositionInLossAndCheckWithdrawal() public {
        giveLiquidity();
        vm.startPrank(msg.sender);
        token.mint();

        token.approve(address(protocol), 5000 ether);
        protocol.depositCollateral(5000 ether);
        protocol.openPositionWithSize(60000 ether, true);

        vm.warp(block.timestamp + 31536000);
        feed.updateAnswer(55000e8);
        protocol.closePosition();
        uint256 collateralAfterClosing = protocol.getCollateralBalance();
        console.log("collateral after Liquidation", collateralAfterClosing);
        (, uint256 size,,,,) = protocol.getPositionDetails(msg.sender);
        assert(size == 0);
        vm.expectRevert(Protocol.Protocol__UserNotHaveEnoughBalance.selector);
        protocol.withdrawCollateral(1e18);
        vm.stopPrank();
    }

    function testLiquidateFuncTraderLossIsMoreThanCollateral() public {
        giveLiquidity();
        vm.startPrank(msg.sender);
        token.mint();

        token.approve(address(protocol), 5000 ether);
        protocol.depositCollateral(5000 ether);
        protocol.openPositionWithSize(60000 ether, true);

        feed.updateAnswer(55000e8);

        (uint256 id,,,,,) = protocol.getPositionDetails(msg.sender);
        console.log("id", id);
        (uint256 leverageRate,) = protocol.checkPositionLeverageAndLiquidability(id);
        console.log("leverageRate", leverageRate);

        (, uint256 sizeBeforeLiqui,,,,) = protocol.getPositionDetails(msg.sender);
        uint256 collateralBeforeLiqui = protocol.getCollateralBalance();
        console.log("size Before Liquidation", sizeBeforeLiqui);
        console.log("collateralBeforeLiqui Before Liquidation", collateralBeforeLiqui);
        vm.stopPrank();

        vm.startPrank(user);
        uint256 balOfVaultbeforeLiq = token.balanceOf(address(vault));
        protocol.liquidatePosition(id);
        (, uint256 sizeAfterLiqui,,,,) = protocol.getPositionDetails(msg.sender);
        console.log("size After Liquidation", sizeAfterLiqui);
        uint256 balOfVaultAfterliq = token.balanceOf(address(vault));
        vm.stopPrank();

        vm.startPrank(msg.sender);
        uint256 collateralAfterLiqui = protocol.getCollateralBalance();
        console.log("collateral after Liquidation", collateralAfterLiqui);
        // 11764705882352941307 leverage = 11x so it's does not need closeing
        console.log("-------------------------------------------------------");
        (int256 checkProfitOrLossForUser) = protocol.checkProfitOrLossForUser(msg.sender);
        vm.stopPrank();
        console.log("checkProfitOrLossForUser", checkProfitOrLossForUser);

        // vault balances
        console.log("balOfVaultbeforeLiq", balOfVaultbeforeLiq);
        console.log("balOfVaultAfterliq", balOfVaultAfterliq);
    }

    function testLiquidateFunction() public {
        giveLiquidity();
        vm.startPrank(msg.sender);
        token.mint();

        token.approve(address(protocol), 5000 ether);
        protocol.depositCollateral(5000 ether);
        protocol.openPositionWithSize(60000 ether, true);

        feed.updateAnswer(57000e8);
        (uint256 id,,,,,) = protocol.getPositionDetails(msg.sender);
        console.log("id", id);
        (uint256 leverageRate,) = protocol.checkPositionLeverageAndLiquidability(id);
        console.log("leverageRate", leverageRate);

        (, uint256 sizeBeforeLiqui,,,,) = protocol.getPositionDetails(msg.sender);
        uint256 collateralBeforeLiqui = protocol.getCollateralBalance();
        console.log("size Before Liquidation", sizeBeforeLiqui);
        console.log("collateralBeforeLiqui Before Liquidation", collateralBeforeLiqui);
        vm.stopPrank();

        uint256 balOfVaultbeforeLiq = token.balanceOf(address(vault));

        vm.startPrank(user);
        protocol.liquidatePosition(id);
        (, uint256 sizeAfterLiqui,,,,) = protocol.getPositionDetails(msg.sender);
        vm.stopPrank();

        vm.startPrank(msg.sender);
        uint256 collateralAfterLiqui = protocol.getCollateralBalance();
        // 11764705882352941307 leverage = 11x so it's does not need closeing
        (uint256 leverageRateafterLiquidatio,) = protocol.checkPositionLeverageAndLiquidability(id);
        assert(leverageRateafterLiquidatio <= LEVERAGE_LIMIT);
        (int256 checkProfitOrLossForUser) = protocol.checkProfitOrLossForUser(msg.sender);
        uint256 balOfVaultAfterliq = token.balanceOf(address(vault));
        vm.stopPrank();
        console.log("size After Liquidation", sizeAfterLiqui);
        console.log("collateral after Liquidation", collateralAfterLiqui);
        console.log("checkProfitOrLossForUser", checkProfitOrLossForUser);

        console.log("balOfVaultbeforeLiq", balOfVaultbeforeLiq);
        console.log("balOfVaultAfterliq", balOfVaultAfterliq);
        // assert((sizeBeforeLiqui*4)/ 3 == sizeAfterLiqui);
    }

    // had to close position when collateral did not decrease
    function testLiquidateFunctWithBorrowingFeeLeverageDidNotDecrease() public {
        giveLiquidity();
        vm.startPrank(msg.sender);
        token.mint();

        token.approve(address(protocol), 5000 ether);
        protocol.depositCollateral(5000 ether);
        protocol.openPositionWithSize(60000 ether, true);
        vm.warp(block.timestamp + 31536000); // Fast forward 1 year

        feed.updateAnswer(57000e8);
        (uint256 id,,,,,) = protocol.getPositionDetails(msg.sender);
        console.log("id", id);
        (uint256 leverageRate,) = protocol.checkPositionLeverageAndLiquidability(id);
        console.log("leverageRate", leverageRate);

        (, uint256 sizeBeforeLiqui,,,,) = protocol.getPositionDetails(msg.sender);
        uint256 collateralBeforeLiqui = protocol.getCollateralBalance();
        console.log("size Before Liquidation", sizeBeforeLiqui);
        console.log("collateralBeforeLiqui Before Liquidation", collateralBeforeLiqui);
        vm.stopPrank();

        vm.startPrank(user);
        console.log("-------------------------------------------------------");
        console.log("balance of protocol", token.balanceOf(address(protocol)));
        uint256 balOfVaultbeforeLiq = token.balanceOf(address(vault));
        protocol.liquidatePosition(id); // After liquidation leverage still more than 15x so the position is closed
        (, uint256 sizeAfterLiqui,,,, bool isInitialized) = protocol.getPositionDetails(msg.sender);
        uint256 collateralOfLiquidator = protocol.getCollateralBalance();
        vm.stopPrank();

        vm.startPrank(msg.sender);

        uint256 collateralOfTraderLiquidated = protocol.getCollateralBalance();
        uint256 balOfVaultAfterLiq = token.balanceOf(address(vault));
        vm.stopPrank();

        assert(isInitialized == false);
        assert(collateralOfLiquidator == (60000e18 * 5) / 1000); // liquidator paid 0.5% of position size
        assert(collateralOfTraderLiquidated <= 351e18);
        console.log("collateral after Liquidation", collateralOfTraderLiquidated);
        console.log("size After Liquidation", sizeAfterLiqui);

        console.log("balOfVaultbeforeLiq", balOfVaultbeforeLiq);
        console.log("balOfVaultAfterliq", balOfVaultAfterLiq);
    }

    function testDecreasePositiRevertDueToHighLeverage() public {
        giveLiquidity();

        vm.startPrank(msg.sender);
        token.mint();

        token.approve(address(protocol), 5000 ether);
        protocol.depositCollateral(5000 ether);
        protocol.openPositionWithSize(60000 ether, true);

        vm.warp(block.timestamp + 31536000); // Fast forward 1 year
        feed.updateAnswer(58000e8);

        console.log("balance BEfore decrese %e:", protocol.getCollateralBalance());
        protocol.decreasePosition(10000 ether);
        console.log("balance After decrese %e:", protocol.getCollateralBalance());
        vm.warp(block.timestamp + 86400); // Fast forward 1 day
        protocol.decreasePosition(10000 ether);
        console.log("balance After 2nd decrese %e:", protocol.getCollateralBalance());
        (, uint256 size, uint256 sizeOfToken,,,) = protocol.getPositionDetails(msg.sender);
        console.log("size", size);
        console.log("size of Token", sizeOfToken);
        assert(size == 40000 ether);
        // 1e18 - (20000e18 * 1e18) / 60000e18 = 666666666666666800 + 1 (20000e18 worth token decrease)
        assert(sizeOfToken < 666666666666666801);
        uint256 priceOfPurchase = protocol.getPriceOfPurchaseByAddress(msg.sender);
        console.log("size ", (sizeOfToken * priceOfPurchase) / 1e18);
    }

    function testBorrowingFees() public {
        // uint256 time = block.timestamp ;
        // console.log("time", time);
        // uint256 borrowingFee = protocol.calculateBorrowFee(10000 ether, 0);
        // console.log("borrowingFee", borrowingFee);
        testForLiquidityResreves();
        giveLiquidity();
        vm.startPrank(msg.sender);
        token.mint();

        token.approve(address(protocol), 5000 ether);
        protocol.depositCollateral(5000 ether);
        protocol.openPositionWithSize(60000 ether, false);
        uint256 id = protocol.getIdByAddress(msg.sender);
        (uint256 leverage, bool isLiquidabale) = protocol.checkPositionLeverageAndLiquidability(id);
        console.log("leverage", leverage);
        assert(leverage == 12e18);
        assert(isLiquidabale == false);

        int256 updateAnswer = 45000e8;
        feed.updateAnswer(updateAnswer);
        (uint256 leverage1, bool isLiquidabale1) = protocol.checkPositionLeverageAndLiquidability(id);
        console.log("leverage", leverage1);
        assert(isLiquidabale1 == false);

        feed.updateAnswer(65000e8);
        (uint256 leverage2, bool isLiquidabale2) = protocol.checkPositionLeverageAndLiquidability(id);
        assert(isLiquidabale2 == true);
        console.log("leverage", leverage2);

        feed.updateAnswer(87000e8);
        (uint256 leverage3, bool isLiquidabale3) = protocol.checkPositionLeverageAndLiquidability(id);
        console.log("leverage", leverage3);

        assert(isLiquidabale3 == true);
        assert(leverage2 == leverage3);

        feed.updateAnswer(63000e8);
        (uint256 leverage4, bool isLiquidabale4) = protocol.checkPositionLeverageAndLiquidability(id);
        console.log("leverage", leverage4);

        assert(isLiquidabale4 == true);

        // uint reward = protocol._calculateLiquidableReward(10000e18);
        // assert(reward == 50e18);
        // uint reward2 = protocol._calculateLiquidableReward(999e18);
        // console.log("reward", reward2);
        // (uint256 remainingSize,uint256 numOfToken) = protocol.decreasePostion(900 ether);
        // uint256 size = 789545484 ether;
        // uint256 token1 = protocol.getNumOfTokenByAmount(size);
        // uint256 price = protocol._getPriceOfPurchase( size, token1);

        // console.log("token", token1);
        // console.log("price", price);
        // assert (borrowingFee == 225 ether);
    }

    function testToCheckIncreasePosition() public {
        address vaultAddr = protocol.getVaultAddress();
        assert(vaultAddr == address(vault));
        testForLiquidityResreves();
        vm.startPrank(msg.sender);
        token.mint();

        token.approve(address(protocol), 100 ether);
        protocol.depositCollateral(100 ether);

        protocol.openPositionWithSize(1000 ether, false);
        (, uint256 sizeBefore,,,,) = protocol.getPositionDetails(msg.sender);
        assert(sizeBefore == 1000 ether);
        console.log("1st Position---------------------------------------");
        protocol.increasePosition(500 ether);
        (, uint256 size,,,,) = protocol.getPositionDetails(msg.sender);
        assert(size == 1500 ether);
        // protocol.liquidityReservesToHold();
        // vm.expectRevert();
        // protocol.increasePosition(600 ether);
    }

    function testForLiquidityResreves() public {
        vm.startPrank(user);
        token.mint();
        token.approve(address(vault), token.balanceOf(user));
        vault.deposit(100 ether, user);
        vm.stopPrank();

        vm.startPrank(user2);
        token.mint();
        token.approve(address(vault), token.balanceOf(user2));
        vault.deposit(100 ether, user2);
        assert(vault.balanceOf(user) == vault.balanceOf(user2));
        vm.stopPrank();

        vm.startPrank(user3);
        token.mint();
        token.approve(address(vault), token.balanceOf(user3));
        vault.deposit(100 ether, user3);
        assert(vault.balanceOf(user3) == vault.balanceOf(user2));
        assert(token.balanceOf(address(vault)) == 300 ether);
        vm.stopPrank();

        vm.startPrank(user4);
        token.mint();
        token.approve(address(vault), token.balanceOf(user4));
        vault.deposit(100 ether, user4);
        assert(vault.balanceOf(user3) == vault.balanceOf(user4));
        assert(token.balanceOf(address(vault)) == 400 ether);
        vm.stopPrank();
    }

    function testOpenDepositCanRevertifSize() public {
        testForLiquidityResreves();
        vm.startPrank(msg.sender);
        token.mint();

        token.approve(address(protocol), 100 ether);
        protocol.depositCollateral(100 ether);

        protocol.openPositionWithSize(1500 ether, false);
        vm.expectRevert();
        protocol.increasePosition(600 ether);

        vm.stopPrank();
    }

    function testDepositWhileLPExistShort() public {
        testForLiquidityResreves();
        vm.startPrank(msg.sender);
        token.mint();
        token.approve(address(protocol), 100 ether);
        protocol.depositCollateral(100 ether);
        protocol.openPositionWithSize(1500 ether, false);

        // Closing Positions -----------------------------------
        int256 updateAnswer = 64000e8;
        feed.updateAnswer(updateAnswer);
        int256 PnL = protocol.checkProfitOrLossForUser(msg.sender);
        console.log("PROFIT", PnL);
        token.balanceOf(address(vault));
        protocol.closePosition();
        assert(token.balanceOf(address(vault)) == 500 ether);
        vm.stopPrank();
    }

    function testToCheckLPsWithdraw() public {
        testForLiquidityResreves();
        giveLiquidity();
        vm.startPrank(user5);
        token.mint();
        token.approve(address(protocol), 100 ether);
        protocol.depositCollateral(100 ether);
        protocol.openPositionWithSize(1000 ether, true);
        vm.stopPrank();

        vm.startPrank(msg.sender);
        token.mint();
        token.approve(address(protocol), 100 ether);
        protocol.depositCollateral(100 ether);
        protocol.openPositionWithSize(1500 ether, false);

        // Price update
        int256 updateAnswer = 5400000000000;
        // int256 updateAnswer = 64000e8;
        feed.updateAnswer(updateAnswer);
        vm.stopPrank();

        // vm.startPrank(user);
        // vault.withdraw(72 ether, user, user);
        // vm.stopPrank();

        vm.startPrank(user2);
        vault.redeem(73 ether, user2, user2);
        vm.stopPrank();

        // vm.startPrank(user3);
        // console.log("vaultBal", token.balanceOf(address(vault)));
        // vault.withdraw(100 ether, user3, user3);
        // vm.stopPrank();
    }

    function testCheckIfUserDoesNotExist() public view {
        int256 num = protocol.checkProfitOrLossForUser(user);
        //    (uint256 totalSize, uint256 totalSizeOfToken) = protocol.getTotalLongPositions();
        // (uint256 totalSizeShr, uint256 totalSizeOfTokenShr) = protocol.getTotalLongPositions();
        //     (uint256 size, uint256 sizeOfToken, bool isLong, bool isInitialized) = protocol.getPositionDetails(user);
        //    console.log(size);
        //    console.log(sizeOfToken);
        //    console.log(isLong);
        //    console.log(isInitialized);
        bool check = protocol.checkLeverageFactorWhileIncreasing(user, 1000 ether);
        console.log(check);
        assert(check == false);

        assert(num == 0);
    }

    function testDepositCollateralAndOpenPosition() public {
        testForLiquidityResreves();
        vm.startPrank(msg.sender);
        token.mint();
        token.approve(address(protocol), 100 ether);
        protocol.depositCollateral(100 ether);
        assert(protocol.getCollateralBalance() == 100 ether);

        // Opening Positions ------------------------------------
        protocol.openPositionWithSize(1500 ether, true);
        assert(protocol.getNumOfOpenPositions() == 1);
        // return (id, size, sizeOfToken, openAt, isLong, isInitialized);

        (, uint256 size, uint256 sizeOfToken,, bool isLong,) = protocol.getPositionDetails(msg.sender);
        console.log("size:", size);
        console.log("sizeOfToken:", sizeOfToken);
        if (isLong) console.log("isLong: TRUE");

        (uint256 totalSize, uint256 totalSizeOfToken) = protocol.getTotalLongPositions();
        console.log(totalSize, "totalSize");
        console.log(totalSizeOfToken, "totalSizeOfToken");

        // Closing Positions -----------------------------------
        int256 updateAnswer = 58000e8;
        feed.updateAnswer(updateAnswer);
        // int256 PnL = protocol.checkProfitOrLossForUser(msg.sender);

        protocol.closePosition();
        (uint256 t1, uint256 t2) = protocol.getTotalLongPositions();
        console.log(t1, "totalSize");
        console.log(t2, "totalSizeOfToken");
        uint256 userBal = protocol.getCollateralBalance();
        assert(userBal == 50 ether);
        // protocol.withdrawCollateral(100 ether);
        vm.stopPrank();
    }

    function testGetterFunctionShoulsdasdNotRevert() public view {
        protocol.checkProfitOrLossForUser(user);
        protocol.getTotalLongPositions();
        protocol.getTotalShortPositions();
        protocol.getPositionDetails(msg.sender);
    }

    function testGetterFunctionShouldNotRevert() public view {
        protocol.checkProfitOrLossForUser(user);
        protocol.getTotalLongPositions();
        protocol.getTotalShortPositions();
        protocol.getPositionDetails(msg.sender);
        protocol.getNumOfOpenPositions();
        protocol.getCollateralBalance();
        protocol.getVaultAddress();
        protocol.getPriceOfBtc();
        protocol.getNumOfTokenByAmount(1 ether);
        protocol.checkLeverageFactorWhileIncreasing(msg.sender, 100);
    }

    function giveLiquidity() internal {
        vm.startPrank(user);
        token.mint();
        token.approve(address(vault), token.balanceOf(user));
        vault.deposit(5000 ether, user);
        vm.stopPrank();

        vm.startPrank(user2);
        token.mint();
        token.approve(address(vault), token.balanceOf(user2));
        vault.deposit(5000 ether, user2);
        assert(vault.balanceOf(user) == vault.balanceOf(user2));
        vm.stopPrank();

        // vm.startPrank(user3);
        // token.mint();
        // token.approve(address(vault), token.balanceOf(user3));
        // vault.deposit(5000 ether, user3);
        // assert(vault.balanceOf(user3) == vault.balanceOf(user2));
        // assert(token.balanceOf(address(vault)) == 15000 ether);
        // vm.stopPrank();

        // vm.startPrank(user4);
        // token.mint();
        // token.approve(address(vault), token.balanceOf(user4));
        // vault.deposit(5000 ether, user4);
        // assert(vault.balanceOf(user3) == vault.balanceOf(user4));
        // assert(token.balanceOf(address(vault)) == 20000 ether);
        // vm.stopPrank();
    }

    //    function testtingERC4626() public view {
    //        uint256 totalAssets = vault.totalAssets();
    //         address coll = vault.asset();
    //         uint256 bal = token.balanceOf(msg.sender);
    //         console.log("totalAssets",totalAssets);
    //         console.log("coll",coll);
    //         console.log("Msg.sender bal:",bal);
    //    }

    //    function testUsageOfVault() public {
    //     // msg sender ------------------------------------------
    //     vm.startPrank(msg.sender);

    //     token.transfer(user2,2e18);
    //     token.transfer(user,5e18);
    //     assert(token.balanceOf(msg.sender) == token.balanceOf(user));
    //     token.approve(address(vault), 5e18);
    //     vault.deposit(5e18, msg.sender);
    //     consoleTotalAssets();

    //     uint256 maxShare = vault.maxMint(msg.sender);
    //     console.log("maxShare",maxShare);

    //     uint256 num = vault.previewDeposit(5e18);
    //     console.log("shares get",num);

    //     uint256 balanceOfshare = vault.balanceOf(msg.sender);
    //     console.log("balanceOfshare",balanceOfshare);
    //     vm.stopPrank();

    //     //USER -------------------------------------------
    //     vm.startPrank(user);
    //     token.approve(address(vault), 5e18);
    //     vault.deposit(5e18, user);
    //     console.log("AFTER 2 shareholder -----------------------");
    //     uint256 UserbalanceOfshare = vault.balanceOf(user);
    //     uint256 UserbalanceOfshare1 = vault.balanceOf(msg.sender);
    //     console.log(UserbalanceOfshare, "UserbalanceOfshare");
    //     console.log(UserbalanceOfshare1, "UserbalanceOfshare1");
    //     vm.stopPrank();

    //     //USER2  -------------------------------------------

    //     vm.startPrank(user2);
    //     token.approve(address(vault), 2e18);
    //     vault.deposit(2e18, user2);
    //     console.log("AFTER 3 shareholder -----------------------");
    //     uint256 UserbalanceOfshare3 = vault.balanceOf(user);
    //     uint256 User2balanceOfshare3 = vault.balanceOf(user2);
    //     uint256 MsgbalanceOfshare3 = vault.balanceOf(msg.sender);
    //     uint256 total = vault.totalSupply();
    //     console.log(UserbalanceOfshare3, "UserbalanceOfshare3");
    //     console.log(User2balanceOfshare3, "User2balanceOfshare3");
    //     console.log(MsgbalanceOfshare3, "MsgbalanceOfshare3");
    //     console.log(total, "total");

    //     console.log("Redeem shares -----------------------");
    //     //  withdraw(uint256 assets, address receiver, address owner)
    //     console.log("balanceBeforeWithdraw", vault.balanceOf(user2));
    //     console.log("balanceBeforeWithdraw Collateral:", token.balanceOf(user2));
    //     uint256 redeemShared = vault.withdraw(2e18, user2, user2);
    //     assert(2e18 == redeemShared);
    //     console.log("balanceAfterWithdraw", vault.balanceOf(user2));
    //     console.log("balanceAfterWithdraw Collateral:", token.balanceOf(user2));
    //     vm.stopPrank();
    //    }
    //     function testUsageOfTransferingVault() public {
    //     vm.startPrank(msg.sender);
    //     token.approve(address(vault), 5e18);
    //     vault.deposit(5e18, user);
    //     token.balanceOf(address(vault));
    //     vm.stopPrank();

    //     vm.startPrank(address(vault));
    //     token.approve(user, type(uint256).max);
    //     vm.stopPrank();

    //     vm.startPrank(address(user));
    //     console.log("USER:", token.balanceOf(address(vault)));
    //     token.transferFrom(address(vault), user, token.balanceOf(address(vault)));
    //     console.log("USER:", token.balanceOf(user));

    //     }

    function consoleTotalAssets() internal view {
        uint256 totalAssets = vault.totalAssets();
        console.log("totalAssets", totalAssets);
    }
}
