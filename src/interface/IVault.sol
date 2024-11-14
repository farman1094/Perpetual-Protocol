// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IVault is IERC4626 {
    error Vault__WithdrawLimitAffectingReserveThreshold();


    // Once Liquidity providers deposited the money they need to keep 15% of their reserves.
    // It also goes up's and down accroding to the situation of profit and loss
    function withdraw(uint256 assets, address receiver, address owner) external override returns (uint256);

    /**
     * @dev See {IERC4626-redeem}.
     */
    function redeem(uint256 shares, address receiver, address owner) external override returns (uint256);

    // Function to get the the amount user have to hold. It depend on the percent we have to hold for all pool.
    function _getAmountToHoldforUser(address _owner)
        external
        view
        returns (uint256 amountToHoldForUser, uint256 balanceOfUser);
}
