// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Protocol} from "src/Protocol.sol";

import {Vault} from "src/Vault.sol";
import {PrepToken} from "src/PrepToken.sol";

import {console} from "forge-std/console.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
// import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract Deployer is Script {
    function run() external returns (MockPriceFeed, PrepToken, Protocol, Vault) {
        MockPriceFeed feed;
        vm.startBroadcast(msg.sender);
        if (block.chainid == 11155111) {
            feed = MockPriceFeed(0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43);
        } else {
            feed = new MockPriceFeed();
        }
        PrepToken token = new PrepToken();
        Protocol protocol = new Protocol(address(token), msg.sender, address(feed));
        Vault vault = new Vault(address(token), protocol);
        protocol.updateVaultAddress(address(vault));
        vm.stopBroadcast();
        return (feed, token, protocol, vault);
    }
}
