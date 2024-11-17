// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Protocol} from "src/Protocol.sol";

import {Vault} from "src/Vault.sol";
import {PrepToken} from "src/PrepToken.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {console} from "forge-std/console.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
import {Handler} from "test/fuzzing/Handler.t.sol";
import {Deployer} from "script/Deployer.s.sol";

contract Invariant is StdInvariant, Test {
    Protocol protocol;
    PrepToken token;
    Vault vault;
    MockPriceFeed feed;
    Handler handler;

    function setUp() public {
        Deployer deployer = new Deployer();
        (feed, token, protocol, vault) = deployer.run();
        handler = new Handler(protocol, token, vault, feed);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveSameValueAsTotalSupply() public view {
        uint256 protocolValue = token.balanceOf(address(protocol));
        uint256 totalSupply = handler.totalDeposited();
        console.log("Total times Run", handler.deposittimesCalled());
        console.log("redeemtimesCalled", handler.redeemtimesCalled());

        assertEq(totalSupply, protocolValue);
    }

    function invariant__GetterViewFunctionShouldNeverRevert() public view {
        address randdomAddress = address(0x123);
        protocol.getVaultAddress();
        protocol.getIdsNotInUse();
        protocol.checkProfitOrLossForUser(randdomAddress);
        protocol.getTotalLongPositions();
        protocol.getTotalShortPositions();
        protocol.getPositionDetails(randdomAddress);
        protocol.getNumOfOpenPositionsIds();
        protocol.getCollateralBalance();
        protocol.getCollateralAddress();
        protocol.getPriceOfBtc();
        protocol.getIdByAddress(randdomAddress);
        // protocol.getPriceOfPurchaseByAddress(randdomAddress);
    }
}
