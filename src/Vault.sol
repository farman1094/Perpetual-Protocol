// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Protocol2} from "src/Protocol2.sol";


contract Vault is ERC4626 {

    error Vault__AlreadyUpdated();
    error Vault__OnlyAdminCanUpdate();
    error Vault__WithdrawLimitAffectingReserveThreshold();


    Protocol2 private protocol;
    address immutable i_ADMIN; // Admin to update Vault Address
    address private protocolAddress;
    bool private alreadyUpdated = false;

    constructor(address assetAddr, address _i_ADMIN) ERC20 ("LP's Token", "LPT")ERC4626 (IERC20(assetAddr)) {
        // Allowance so the protocol can withdraw money
        IERC20(assetAddr).approve(protocolAddress, type(uint256).max);
        i_ADMIN = _i_ADMIN;
    }


        function updateProtocolAddress(address _protocolAddress) external {
        if(alreadyUpdated) revert Vault__AlreadyUpdated();
        if(msg.sender != i_ADMIN) revert Vault__OnlyAdminCanUpdate();

        protocolAddress = _protocolAddress;
        alreadyUpdated = true;

    }
    


    // Need to update the LP's cannot withdraw when the position is opened

     function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }

        uint256 amountToHold = Protocol2(protocolAddress).liquidityReservesToHold();
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
        uint256 amountToHold = Protocol2(protocolAddress).liquidityReservesToHold();
        uint256 totalSupplyOfToken = totalSupply();
        if((totalSupplyOfToken - assets) < amountToHold){
            revert Vault__WithdrawLimitAffectingReserveThreshold();
        }

        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

}
