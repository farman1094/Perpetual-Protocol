// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract PrepToken is ERC20 {


    error PrepToken__OnlyMintAfter1Day(uint256);
    mapping(address => uint256) lastMintedAt;
    constructor() ERC20("Prep Token", "PPT") {
    }


    /**@dev Limit of minting only mint 5 ether in a day*/
    function mint() external {
        if(block.timestamp > (lastMintedAt[msg.sender] + 1 days)){
            revert PrepToken__OnlyMintAfter1Day(block.timestamp);
        }
        _mint(msg.sender, 100 ether);
        lastMintedAt[msg.sender] = block.timestamp;
    }

}