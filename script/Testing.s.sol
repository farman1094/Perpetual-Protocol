// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.24;

// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// import {Vault} from "src/Vault.sol";
// import {Protocol2} from "src/Protocol2.sol";
// import {PrepToken} from "src/PrepToken.sol";


// import {console} from "forge-std/console.sol";
// import {Script} from "forge-std/Script.sol";



// contract DeployProtocol is Script {
//     PrepToken token;
//     Vault vault;
//     Protocol2 protocol;
    
//     address constant ADMIN =    0x264F7948c23da2233D3458F1B4e2554f0e56c9Ca;
//     function run() public {


//         vm.startBroadcast(msg.sender);
        
//         token = new PrepToken();
//         vault = new Vault(address(token), ADMIN);
//         protocol = new Protocol2(address(token), vault);


//         vm.stopBroadcast();

//         }
        


// //     try shareToken.totalAssets() returns (uint256 assets) {
// //     console.log("totalAssets", assets);
// // } catch Error(string memory reason) {
// //     console.log("Error reason:", reason);
// // } catch (bytes memory lowLevelData) {
// //     console.logBytes( lowLevelData);
// // }




//         // bool success = token.approve(erc, IERC20(collateral).balanceOf(msg.sender));
//         // require(success);
// }
//     // forge script script/Testing.s.sol:Testing --rpc-url $SEPOLIA_RPC_URL
//     // forge script script/Testing.s.sol:Testing --rpc-url $SEPOLIA_RPC_URL --account main --stopBroadcast --verify --etherscan-api-key $ESCAN_API_KEY -vvvv


