// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("USDC", "USDC") {
        _mint(msg.sender, 12e18);
    }


    /// Need to update withdraw and redemmed function to make sure Liquidity providers cannot withdraw when the positions is open or reserved
    
}