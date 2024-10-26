// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Protocol} from "src/Protocol.sol";

contract ProtocolTest is Test {
Protocol protocol;
    function setUp() public {
        protocol = new Protocol();
    }

    function testToCheckPrice() public {
        int256 price = protocol.getPriceOfBtc();
        console.log(price);
    }
}