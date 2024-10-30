# Minimal Perpetual Trading Protocol

This protocol is designed as a minimal, proof-of-concept implementation of a perpetual trading system. While streamlined compared to real-world perpetual trading protocols, it incorporates core features to allow leveraged trading on BTC, including long and short positions, collateral management, and liquidity provision.

### Addresses
PrepToken Address :  
Vault Address:  
Protocol Address: 


---

## Table of Contents
1. [Protocol Overview](#protocol-overview)
2. [Key Features](#key-features)
3. [Role of Parties](#role-of-parties)
4. [Smart Contracts and Functions](#smart-contracts-and-functions)
5. [Usage Instructions](#usage-instructions)
6. [Important Links](#important-links)

---

## Protocol Overview

The Minimal Perpetual Trading Protocol facilitates leveraged trading on BTC, enabling traders to take long or short positions. The protocol is balanced by liquidity providers (LPs) who deposit funds into a shared vault, covering potential trading losses and receiving leverage fees in return. This system manages trades and collateral through a series of smart contracts and is designed for simplicity, minimizing additional protocol fees and complex features.

---

## Key Features

- **Leveraged BTC Trading**: Allows traders to open long (betting on price increase) or short (betting on price decrease) positions on BTC.
- **Collateral Management**: Traders deposit collateral, and LPs back the system by providing liquidity.
- **Profit and Loss Distribution**: Profits and losses are balanced across opposing positions; if necessary, the vault covers excess losses.
- **Liquidity Provider Vault**: LPs deposit funds into the vault, where funds are distributed as shares using the ERC-4626 standard, granting LPs a proportional share in vault profits and losses.
- **Flexible Withdrawal Constraints for LPs**: LPs must retain a percentage of their assets in the vault to ensure protocol stability.

---

## Role of Parties

### 1. Traders
Traders deposit collateral to open leveraged positions on BTC, which can be long or short. They use the `Protocol` contract to manage trades, deposit collateral, and calculate their leverage.

### 2. Liquidity Providers (LPs)
LPs contribute liquidity to the protocol’s `Vault`, enabling the system to cover potential trader losses. In return, LPs earn leverage fees and receive shares in the vault, calculated based on the ERC-4626 standard.

### 3. Admin
The Admin is responsible for setting the vault address within the protocol. This role has limited involvement in day-to-day operations but is essential for initial protocol setup.

---

## Smart Contracts and Functions

### 1. **Prep Token**

The `PrepToken` is an ERC-20 token used within the protocol, pegged to $1 for simplicity. It serves as collateral for both traders and liquidity providers (LPs) when interacting with other contracts in the protocol. The token has 18 decimals (`1e18` PPT = $1), facilitating easy calculations and uniformity across contract interactions.

### 2. **Vault (Liquidity Provider Vault)**

The `Vault` contract, using the ERC-4626 standard, stores funds deposited by LPs. In exchange, LPs receive shares representing their proportional ownership of the vault’s assets. These shares are dynamically adjusted based on the protocol's profit and loss to maintain protocol stability. The vault interacts directly with the protocol in profit and loss scenarios:

- **Profit Distribution**: Funds are pulled from the vault to pay out traders’ profits.
- **Loss Coverage**: Losses are returned to the vault, which are then proportionally distributed back to LPs based on their shares.

#### Withdrawal Constraints for LPs:
   - LPs must retain a percentage (default 15%) of their collateral in the vault. This percentage adjusts based on protocol profits or losses to ensure consistent liquidity.
   - Example: If the protocol has a 15% reserve requirement and LP deposits $100, they can withdraw up to $85, with $15 reserved.

### 3. **Protocol (Core Trading Contract)**

The `Protocol` contract manages trader actions, including depositing collateral, opening positions, adjusting leverage, and handling profit/loss scenarios. Below are detailed descriptions of key functions:

#### Core Functions for Traders

1. **`depositCollateral(uint256 amount)`**
   - **Purpose**: Allows traders to deposit collateral into the protocol, which is then used to determine leverage eligibility.
   - **Parameters**:
     - `amount` (uint256): The amount of `PrepToken` (PPT) the trader wishes to deposit (e.g., `1e18` PPT = $1).
   - **Usage**:
     - Before depositing, the trader must approve the `Protocol` contract to spend `PrepToken` using `approve(address spender, uint256 amount)`.
     - Upon depositing, this collateral becomes the basis for the trader's leverage limit.
   - **Example**:
     - If a trader deposits `100 PPT`, they can borrow up to 15x that amount.

2. **`openPosition(uint256 _size, uint256 _sizeOfToken, bool _isLong)`**
   - **Purpose**: Opens a leveraged position, either long (betting BTC will increase) or short (betting BTC will decrease).
   - **Parameters**:
     - `_size` (uint256): The total amount the trader wishes to borrow (leverage).
     - `_sizeOfToken` (uint256): The number of BTC tokens desired. If set to `0`, the contract will automatically calculate the number of tokens based on `_size` and BTC price.
     - `_isLong` (bool): `true` if the trader is opening a long position, `false` for a short position.
   - **Usage**:
     - `_size` must be less than or equal to `depositCollateral * 15`.
     - `_sizeOfToken` * `BTC Price` should also be ≤ `_size` (or the function calculates `_sizeOfToken` if set to `0`).
   - **Example**:
     - A trader with `100 PPT` collateral can open a long position with `_size` up to `1500 PPT`.

3. **`increasePosition(uint256 additionalSize)`**
   - **Purpose**: Increases an existing position if the trader has unused collateral for leverage. Traders in a loss cannot increase their position until they close it.
   - **Parameters**:
     - `additionalSize` (uint256): The additional leverage amount the trader wishes to add to their open position.
   - **Usage**:
     - Traders must still stay within their leverage limit.
   - **Example**:
     - If the trader has an open position of `1000 PPT` but unused leverage of `500 PPT`, they can call `increasePosition(500)` to maximize leverage.

4. **`closePosition()`**
   - **Purpose**: Closes an open position and settles any profit or loss. The protocol deducts losses from the trader's collateral, while profits are paid out.
   - **Parameters**: None.
   - **Usage**:
     - If a loss exceeds the trader’s collateral, all collateral is taken, but no further tracking occurs for uncovered losses.
   - **Example**:
     - If the trader’s collateral is `100 PPT` and the position closes with a `150 PPT` loss, the entire `100 PPT` collateral is forfeited.

5. **`withdrawCollateral(uint256 amount)`**
   - **Purpose**: Withdraws the trader's collateral from the protocol, provided there are no open positions.
   - **Parameters**:
     - `amount` (uint256): The amount of collateral the trader wishes to withdraw.
   - **Usage**:
     - This function only works if the trader has no active positions.
   - **Example**:
     - A trader with `100 PPT` in collateral can withdraw the full amount after closing all positions.


  
---

#### Additional Trader Functions:
   - `getPositionDetails(address user)`: Retrieve a trader’s position.
   - `getPriceOfBtc()`: Fetches the current BTC price.
   - `getNumOfTokenByAmount(uint256 amount)`: Calculates BTC tokens by amount.
   - `checkLeverageFactor(address sender, uint256 _size)`: Checks leverage eligibility.
   - `getVaultAddress()` and `getCollateralAddress()`: Accesses protocol contract addresses.

---

## Usage Instructions

### **For Traders**

1. **Obtain Prep Tokens**: Use the `mint()` function in `PrepToken` to acquire $100 (100 PPT).
2. **Approve Protocol**: In the `PrepToken` contract, approve the `Protocol` contract to use your tokens with `approve(address spender, uint256 amount)`.
3. **Deposit Collateral**: Call `depositCollateral(uint256 amount)` to fund your account.
4. **Open Position**: Use `openPosition(uint256 _size, uint256 _sizeOfToken, bool _isLong)` to start trading.
   - Example: `_isLong = true` for long positions (expecting BTC price increase), `_isLong = false` for short positions.
5. **Increase or Close Positions**: 
   - Increase position size if eligible (no active loss).
   - Close positions to settle dues or withdraw funds.
6. **Withdraw Collateral**: Once all positions are closed, use the `withdrawCollateral()` function to reclaim your funds.

### **For Liquidity Providers**

1. **Obtain Prep Tokens**: Use the `mint()` function in `PrepToken` to get $100 (100 PPT).
2. **Approve Protocol**: Grant the `Vault` contract approval in `PrepToken` using `approve(address spender, uint256 amount)`.
3. **Deposit or Mint Shares**:
   - **Deposit**: Use the deposit function to specify assets, receiving corresponding shares.
   - **Mint**: Specify the share amount to mint; the vault calculates the asset equivalent.
4. **Withdraw or Redeem Shares**:
   - **Withdraw**: Enter the asset amount to withdraw, and receive proportional shares.
   - **Redeem**: Input the share amount to redeem, receiving corresponding assets.
   - **Holding Requirements**: LPs must maintain a minimum collateral percentage as described above.
---
## Important Links

For further details, in-depth guides, and community support, please refer to the following resources:

- **ERC-20 Overview**: [OpenZeppelin ERC-20 Documentation](https://docs.openzeppelin.com/contracts/4.x/erc20)  
  A detailed explanation of the ERC-20 standard, which the `PrepToken` contract follows to ensure compatibility and seamless interactions across the protocol.

- **ERC-4626 Overview**: [OpenZeppelin ERC-4626 Documentation](https://docs.openzeppelin.com/contracts/4.x/erc4626)  
  Reference on ERC-4626, the tokenized vault standard used in the protocol’s `Vault` contract, detailing the liquidity management approach.

This protocol offers a streamlined, decentralized trading environment where both traders and liquidity providers participate in a balanced and minimized perpetual trading structure. Through careful contract design and limited but flexible roles, the protocol serves as a foundational template for perpetual trading systems.