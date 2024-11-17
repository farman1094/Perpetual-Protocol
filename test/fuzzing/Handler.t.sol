// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Protocol} from "src/Protocol.sol";
import {Vault} from "src/Vault.sol";
import {PrepToken} from "src/PrepToken.sol";
import {console} from "forge-std/console.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";

contract Handler is Test {
    Protocol protocol;
    PrepToken token;
    Vault vault;
    MockPriceFeed feed;

    address[] public userWithCollateralDeposited;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; // max unit 96 value
    // // uint256 public MinttimesCalled;
    // // uint256 public halfMinttimesCalled;
    uint256 public redeemtimesCalled;
    // // uint256 public halfredeemtimesCalled;
    uint256 public deposittimesCalled;
    uint256 public totalDeposited;

    constructor(Protocol _protocol, PrepToken _token, Vault _vault, MockPriceFeed _feed) {
        protocol = _protocol;
        token = _token;
        vault = _vault;
        feed = _feed;
    }

    function depositCollateral(uint256 amountCollateral) public {
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        token.mintRandom(amountCollateral);
        token.approve(address(protocol), amountCollateral);
        totalDeposited += amountCollateral;
        protocol.depositCollateral(amountCollateral);
        vm.stopPrank();
        userWithCollateralDeposited.push(msg.sender);
        deposittimesCalled++;
    }

    function redeemCollateral(uint256 amountCollateral) public {
        vm.startPrank(msg.sender);
        uint256 maxCollateral = protocol.getCollateralBalance();

        amountCollateral = bound(amountCollateral, 0, maxCollateral);
        if (amountCollateral == 0) {
            return;
        }
        totalDeposited -= amountCollateral;
        protocol.withdrawCollateral(amountCollateral);
        redeemtimesCalled++;
        vm.stopPrank();
    }
}
