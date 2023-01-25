# blueberry-core v1 

## Protocol Summary

Blueberry Core v1 is an upgrade and fork from Alpha Homora v2, a leveraged yield-farming product. Here are some key features:

The protocol is integrated with existing lending protocol. Whenever a user wants to borrow funds (on leverage) to yield farm additionally, Blueberry will borrow from the lending protocol.

- A wide varitey of assets are borrow-able, including stables like USDC, USDT, DAI.
- Each "spell" defines how the protocol interacts with the concentrated liquidity vaults, e.g. Ichi vault.
  - Spell functions include e.g. `depositInternal`, `withdrawInternal`.
- Adjustable positions - users can adjust their existing positions by supply more assets, borrow more assets, or repay some debts.
  - As long as the collateral credit >= borrow credit. Otherwise, the position is at liquidiation risk.
  
## Protocol Components

- BlueberryBank
  - Store each position's collateral tokens (in the form of wrapped NFT tokens)
  - Users can execute "spells", e.g. opening a new position, closing/adjusting existing position.
- Spells (e.g. Ichi,Uniswap/Sushiswap/Curve/...)
  - Define how to interact with each pool
  - Execute `borrow`/`repay` assets by intereacting with the bank, which will then interact with the lending protocol.
  
### Component Interaction Flow

1. User -> BlueberryBank.
   User calls `execute` to BlueberryBank, specifying which spell and function to use, e.g. `depositInternal` using IchiVaultSpell.
2. BlueberryBank -> Spell
3. Spell may call BlueberryBank to e.g. `doBorrow` funds and `doRepay` debt. Funders are then sent to Spell. to execute pool interaction.   
4. Spells -> Pools   
   Spells interact with Pools (e.g. optimally swap before supplying to Uniswap, or removing liquidity from the pool and pay back some debts).
5. (Optional) Stake LP tokens in wrapper contracts (e.g. WStakingRewards for Uniswap + Balancer).
6. Spell may put collateral back to BlueberryBank.
   If the spell function called is e.g. to open a new position, then the LP tokens will be stored in BlueberryBank.
   
## Example Execution

### putCollateral

1. User calls `execute(0, USDT, WETH, data)` on BlueberryBank contract. `data` encodes IchiVaultSpell function call with arguments (including how much of each asset to supply, to borrow, and slippage control settings).
2. BlueberryBank uses data call to encoded `putCollateral` function call with arguments) to IchiVaultSpell.
3. IchiVaultSpell executes `putCollateralWERC20`
  - `doBorrow` from the lending protocol
  - Optimally swap assets and add liquidity to Uniswap pool
  - Wrap LP tokens to wrapper WERC20 (toget ERC 1155)
  - `doPutCollateral` wrapped tokens back to BlueberryBank
  - Refund leftover assets to the user.
  
<!---  >For **Uniswap** pools with staking rewards, use `putCollateralWStakingRewards` function.
>For **Sushiswap** pools with staking in masterchef, use `putCollateralWMasterChef` function.
>For **Balancer** pools with staking rewards, use `putCollateralWStakingRewards` function.
>For all **Curve** pools, use `putCollateral[N]` (where `N` is the number of underlying tokens). The spell will auto put in Curve's liquidity guage. --->

## Oracle 

Prices are determined in USD.

- For regular assets, asset prices can be derived from Chainlink, Band, or Uniswap feeds.
- For LP tokens, asset prices will determine the optimal reserve proportion of the underlying assets, which are then used to compoute the value of LP tokens. See `Uniswapv3AdpaterOracle.sol` for example implementation.
   
