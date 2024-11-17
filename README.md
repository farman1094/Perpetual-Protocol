# Minimal Perpetual Trading Protocol

This protocol is a foundational, decentralized system for perpetual trading on BTC. It integrates core functionalities such as leveraged trading, collateral management, liquidity provisioning, and liquidation mechanisms. Designed for simplicity and robustness, it provides a secure environment for traders and liquidity providers (LPs) while incorporating advanced features like real-time leverage calculations, borrowing fees, and dynamic reserve management.    


### Addresses
**Protocol:**  
 **Vault:**  
 **PrepToken:** 
 
---

## Table of Contents
1. [Overview](#overview)
2. [Key Features](#key-features)
3. [Role of Parties](#role-of-parties)
4. [Smart Contracts](#smart-contracts)
5. [Key Functions](#key-functions)
6. [Usage Instructions](#usage-instructions)
7. [Important Links](#important-links)

---

## Overview

The Minimal Perpetual Trading Protocol facilitates leveraged trading on BTC through a decentralized system. Traders can open long or short positions, while liquidity providers back the system with funds. The protocol ensures stability via collateralized reserves, borrowing fees, and liquidation mechanisms. By streamlining essential trading features, this protocol serves as a proof-of-concept for perpetual trading systems.

---

## Key Features

- **Leveraged Trading**: Offers up to 15x leverage for traders, with real-time leverage tracking to ensure system stability.
- **Dynamic Reserve Management**:  Maintains 15% reserves for open positions, adjusting based on profit and loss scenarios, as well as the difference between long and short positions.
- **Borrowing Fees**: Traders pay a borrowing fee on reserves held by the protocol, calculated at 15% annually.
- **Collateral Flexibility**: Traders can withdraw collateral even with open positions, provided leverage remains within limits.
- **Liquidation Mechanism**: Automatically liquidates positions exceeding 30x leverage, rewarding liquidators with 0.5% of the liquidated position.
- **ERC-4626 Vault**: Implements tokenized liquidity shares for LPs, dynamically adjusting based on protocol profits and losses.

---

## Role of Parties

### 1. Traders
Traders open leveraged positions on BTC by depositing collateral. They can manage positions using functions for increasing, decreasing, or closing trades.

### 2. Liquidity Providers (LPs)
LPs deposit funds into the protocol’s vault to provide liquidity. In return, they earn fees and receive proportional shares of vault profits.

### 3. Admin
The Admin configures initial protocol settings, such as vault address. 

### 4. Liquidators (Arbitary actors)
Independent actors who monitor leverage levels. Liquidators can close over-leveraged positions for a 0.5% reward of the liquidated position size.

---

## Smart Contracts

### 1. **PrepToken**
An ERC-20 token pegged to $1, used as collateral for traders and liquidity providers.

### 2. **Vault (ERC-4626)**
Holds liquidity from LPs, distributing shares proportionally. Reserves are dynamically adjusted based on trader activity.

### 3. **Protocol**
The core contract managing trader positions, collateral, leverage, and liquidation processes.

---

## Key Functions

### Trader Functions

#### **Opening Positions**
1. **`openPositionWithSize(uint256 _size, bool _isLong)`**
   - Opens a position by specifying the size.
   - Validates that the vault holds 15% of the position size for reserves.

2. **`openPositionWithToken(uint256 _sizeOfToken, bool _isLong)`**
   - Opens a position by specifying the token amount.
   - Automatically calculates the position size based on the BTC price.

#### **Managing Positions**
1. **`increasePosition(uint256 _size)`**
   - Adds to an open position. Allowed even in loss, provided leverage remains ≤ 15x.

2. **`decreasePosition(uint256 _size)`**
   - Reduces the size of an open position, adjusting collateral and profit/loss proportionally.

3. **`closePosition()`**
   - Fully closes a position, settling any profit or loss.

#### **Collateral Management**
1. **`depositCollateral(uint256 amount)`**
   - Deposits collateral into the protocol.

2. **`withdrawCollateral(uint256 amount)`**
   - Withdraws collateral, even with open positions, if leverage remains ≤ 15x.

#### **Liquidation**
1. **`checkPositionLeverageAndLiquidability(uint id)`**
   - Checks if a position exceeds 30x leverage and is liquidatable.

2. **`liquidatePosition(uint id)`**
   - Liquidates a position exceeding 30x leverage, reducing its size by one-third and awarding 0.5% of the position size to the liquidator.

---

### LP Functions

1. **`deposit(uint256 amount)`**
   - Deposits liquidity into the vault, receiving proportional shares.

2. **`withdraw(uint256 amount)`**
   - Withdraws liquidity, adhering to reserve constraints.

3. **`redeem(uint256 shares)`**
   - Redeems shares for underlying assets.

---
### **Position Management**

Position management covers the processes for LPs withdrawing funds, users opening positions, and ensuring the protocol's liquidity reserves are maintained. Below are the key aspects and functions involved:

### Liquidity Reserves Calculation: `liquidityReservesToHold()`

- **Purpose**: The **`liquidityReservesToHold()`** function calculates the amount of reserves required to support both existing and new positions.
- **Calculation**: The reserves are now determined by **15% of the difference** between long and short positions, considering any **profits and losses** from previous trades. This ensures the protocol has enough liquidity to support ongoing trades.
- **Usage**:
  - **LPs with Drawn Funds**: Before LPs can withdraw money, the protocol checks if  this withdrawal will not affect the current position existed, based on this calculated reserve. If the current reserves are sufficient after the withdrawal to cover the positions’s then good otherwise, the action will be halted.
  - **New Positions**: Before users can open new positions, the protocol checks that there are enough reserves available to maintain both the new position and existing ones. This ensures that the liquidity vault is sufficiently funded to handle new trades without compromising existing positions.

---

### Calculations and Fees

#### **Real-Time Leverage**
Calculated as:  
`leverage = position / (collateral + PnL)`  
- Profit is added. 
- loss is subtracted.

#### **Borrowing Fee**
- Annual fee: 15% of reserves held for the position.
- Formula:  
  `borrowingFee = reserveAmount * timePassed * (15% / 1 year)`

#### **Liquidation Fee**
- 0.5% of the liquidated position size.

---

## Usage Instructions

### For Traders

1. **Acquire Prep Tokens**: Use the `mint()` function in the `PrepToken` contract.
2. **Approve Protocol**: Allow the `Protocol` contract to spend tokens with `approve()`.
3. **Deposit Collateral**: Use `depositCollateral()` to fund your account.
4. **Open Positions**: Use either `openPositionWithSize()` or `openPositionWithToken()` based on preference.
5. **Manage Positions**:
   - Increase: Use `increasePosition()`.
   - Decrease: Use `decreasePosition()`.
   - Close: Use `closePosition()`.
6. **Withdraw Collateral**: Call `withdrawCollateral()` after closing positions or ensuring leverage ≤ 15x.

### For LPs

1. **Acquire Prep Tokens**: Use the `mint()` function.
2. **Approve Vault**: Allow the vault to spend tokens with `approve()`.
3. **Deposit Liquidity**: Use `deposit()` to receive proportional shares.
4. **Withdraw or Redeem**:
   - Withdraw: Specify the asset amount.
   - Redeem: Specify the share amount.

### For Liquidators

1. **Monitor Positions**:  
   Use the `getNumOfOpenPositionsIds()` function to retrieve the list of open positions. For example, if it returns 5, the open position IDs are `(1, 2, 3, 4, 5)`. If it returns 0, there are no open positions at the moment.

2. **Identify Unused IDs**:  
   Use `getIdsNotInUse()` to get the IDs that are not assigned to any active positions. For example, if it returns `[3, 4]`, it means these IDs are available, and the open positions are `[1, 2, 5]`.

3. **Check Leverage and Liquidation Status**:  
   For each open position ID, use `checkPositionLeverageAndLiquidability(uint id)` to check if it is eligible for liquidation. This function returns a tuple:  
   `(uint256 leverageRate, bool isLiquidable)`  
   - `leverageRate`: The current leverage of the position.
   - `isLiquidable`: Whether the position is liquidable based on its leverage rate.  
   A position is liquidatable if `leverageRate > 30x` and `isLiquidable` is `true`.

4. **Liquidate Position**:  
   If the position is liquidatable, use `liquidatePosition(uint id)` to liquidate that position. Liquidating a position rewards the liquidator with 0.5% of the position's size, which will be added to the liquidator’s balance. This reward can be withdrawn using the `withdrawCollateral()` function or used for further trading.  
   **Note**: A trader cannot liquidate their own position.

--- 

## Important Links

- [ERC-20 Overview](https://docs.openzeppelin.com/contracts/4.x/erc20)  
- [ERC-4626 Overview](https://docs.openzeppelin.com/contracts/4.x/erc4626)  

--- 

This protocol provides a streamlined and secure environment for perpetual trading, balancing simplicity with robust risk management. Whether you're a trader, LP, or liquidator, the system ensures transparency, fairness, and efficiency.