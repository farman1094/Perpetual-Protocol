// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Protocol2} from "src/Protocol2.sol";
import {console} from "forge-std/console.sol";



contract Vault is ERC4626 {

  
    error Vault__WithdrawLimitAffectingReserveThreshold();


    Protocol2 private protocol;

    constructor(address assetAddr, Protocol2 _protocol) ERC20 ("LP's Token", "LPT")ERC4626 (IERC20(assetAddr)) {
        // Allowance so the protocol can withdraw money
        protocol = _protocol;
        IERC20(assetAddr).approve(address(protocol), type(uint256).max);
     
    }


    //     function updateProtocolAddress(address _protocolAddress) external {
    //     if(alreadyUpdated) revert Vault__AlreadyUpdated();
    //     if(msg.sender != i_ADMIN) revert Vault__OnlyAdminCanUpdate();

    //     protocolAddress = _protocolAddress;
    //     alreadyUpdated = true;

    // }
    


    // Need to update the LP's cannot withdraw when the position is opened

     function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }

        uint256 amountToHold = protocol.liquidityReservesToHold();
        console.log("amountToHold",amountToHold);
        uint256 totalSupplyOfToken = totalSupply();
        if((totalSupplyOfToken - assets) < amountToHold){
            revert Vault__WithdrawLimitAffectingReserveThreshold();
        }

        uint256 shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

    /** @dev See {IERC4626-redeem}. */
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }

        uint256 assets = previewRedeem(shares);
        uint256 amountToHold = protocol.liquidityReservesToHold();
        uint256 totalSupplyOfToken = totalSupply();
        if((totalSupplyOfToken - assets) < amountToHold){
            revert Vault__WithdrawLimitAffectingReserveThreshold();
        }

        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

}
