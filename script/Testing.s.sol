// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vault} from "src/Vault.sol";
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";




contract Testing is Script {
    address public collateral = 0xD5457C30d3fA8DED4abD8bC4450c55D43aCEEe2F; 
    // address public erc4626 = 0x2AF9bD623F155987c78201477a4B25aE8c4c3eB1;
    address public erc4626 = 0x2AF9bD623F155987c78201477a4B25aE8c4c3eB1;
    IERC4626 public shareToken = IERC4626(erc4626);
    IERC20 public token = IERC20(collateral);
    function run() public {


        vm.startBroadcast(msg.sender);
        //    function approve(address spender, uint256 value) external returns (bool);
        uint256 bal = token.balanceOf(msg.sender);
        console.log("bal",bal);
        uint256 totalAssets = shareToken.totalAssets();

        address coll = shareToken.asset();

        console.log("totalAssets",totalAssets);

        console.log("coll",coll);

    


        }
        


//     try shareToken.totalAssets() returns (uint256 assets) {
//     console.log("totalAssets", assets);
// } catch Error(string memory reason) {
//     console.log("Error reason:", reason);
// } catch (bytes memory lowLevelData) {
//     console.logBytes( lowLevelData);
// }




        // bool success = token.approve(erc4626, IERC20(collateral).balanceOf(msg.sender));
        // require(success);
}
    // forge script script/Testing.s.sol:Testing --rpc-url $SEPOLIA_RPC_URL
    // forge script script/Testing.s.sol:Testing --rpc-url $SEPOLIA_RPC_URL --account main --broadcast --verify --etherscan-api-key $ESCAN_API_KEY -vvvv


