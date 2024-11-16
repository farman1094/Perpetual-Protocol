// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Protocol} from "src/Protocol.sol";
import {console} from "forge-std/console.sol";

/**
 * @title Vault
 * @author Mohd Farman
 * This system is designed to be as minimal as possible.
 * NOTE This system accept PrepToken as a collateral
 * It woks as an pool for Protocol
 * In this system the Liquidity Providers deposit money
 * In exchange of collateral LP get shares
 */
contract Vault is ERC4626 {
    error Vault__WithdrawLimitAffectingReserveThreshold();

    Protocol private protocol;

    constructor(address assetAddr, Protocol _protocol) ERC20("LP's Token", "LPT") ERC4626(IERC20(assetAddr)) {
        protocol = _protocol;
        // Allowance so the protocol can withdraw money
        IERC20(assetAddr).approve(address(protocol), type(uint256).max);
    }

    // Once Liquidity providers deposited the money they need to keep 15% of their reserves.
    // It also goes up's and down accroding to the situation of profit and loss
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }

        // changes here
        (uint256 amountToHoldForUser, uint256 balanceOfUser) = _getAmountToHoldforUser(owner);
        if ((balanceOfUser - assets) < amountToHoldForUser) {
            revert Vault__WithdrawLimitAffectingReserveThreshold();
        }

        uint256 shares = previewWithdraw(assets);
        console.log(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
        return shares;
    }

    /**
     * @dev See {IERC4626-redeem}.
     */
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }
        uint256 assets = previewRedeem(shares);

        (uint256 amountToHoldForUser, uint256 balanceOfUser) = _getAmountToHoldforUser(owner);
        console.log("redeem", amountToHoldForUser);
        if ((balanceOfUser - assets) < amountToHoldForUser) {
            revert Vault__WithdrawLimitAffectingReserveThreshold();
        }

        _withdraw(_msgSender(), receiver, owner, assets, shares);
        return assets;
    }

    // Function to get the the amount user have to hold. It depend on the percent we have to hold for all pool.
    function _getAmountToHoldforUser(address _owner)
        internal
        view
        returns (uint256 amountToHoldForUser, uint256 balanceOfUser)
    {
        balanceOfUser = balanceOf(_owner);
        uint256 amountToHold = protocol.liquidityReservesToHold();
        if (amountToHold == 0) {
            return (0, balanceOfUser);
        }
        uint256 totalSupplyOfToken = totalAssets();
        uint256 percentToHold = ((amountToHold * 100) / totalSupplyOfToken);
        amountToHoldForUser = (balanceOfUser / 100) * percentToHold;

        return (amountToHoldForUser, balanceOfUser);
    }
}
