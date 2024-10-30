// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Vault 
 * @author Mohd Farman
 * This system is simple implementation of ERC20.
 */

contract PrepToken is ERC20 {

    error PrepToken__OnlyMintAfter1Day(uint256);

    mapping(address => uint256) s_lastMintedAt;

    constructor() ERC20("Prep Token", "PPT") {
    }


    /**@dev Limit of minting only mint 5 ether in a day*/
    function mint() external {
        if(block.timestamp > (s_lastMintedAt[msg.sender] + 86400 )){
            revert PrepToken__OnlyMintAfter1Day(block.timestamp);
        }
        _mint(msg.sender, 100 ether);
        s_lastMintedAt[msg.sender] = block.timestamp;
    }

}