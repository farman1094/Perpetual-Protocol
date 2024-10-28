// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { MockV3Aggregator } from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract MockPriceFeed is MockV3Aggregator {
    
    constructor() MockV3Aggregator(8, 6893539421739) {    
    }
}


// 68935,39,421,739
