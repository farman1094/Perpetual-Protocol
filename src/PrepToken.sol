// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Vault
 * @author Mohd Farman
 * This system is simple implementation of ERC20.
 */
contract PrepToken is ERC20 {
    constructor() ERC20("Prep Token", "PPT") {}

    /**
     * @dev Limit of minting only mint 5 ether in a day
     */
    function mint() external {
        _mint(msg.sender, 6000 ether);
    }

    function mintRandom(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}
