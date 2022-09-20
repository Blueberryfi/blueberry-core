# blueberry-core v1 

## Protocol Summary

Blueberry Core v1 is an upgrade and fork from Alpha Homora v2, a leveraged yield-farming product. Here are some key features:

<!-- The protocol is integrated with existing lending protocol. Whenever a user wants to borrow funds (on leverage) to yield farm additionally, Blueberry will borrow from the lending protocol. -->

- A wide varitey of assets are borrow-able, including stables like USDC, USDT, DAI.
- Each "spell" defines how the protocol interacts with the concentrated liquidity vaults, e.g. Ichi vault.
  - Spell functions include e.g. `addLiquidity`, `removeLiquidity`.
- Adjustable positions - users can adjust their existing positions by supply more assets, borrow more assets, or repay some debts.
  - As long as the collateral credit >= borrow credit. Otherwise, the position is at liquidiation risk.
  
## Protocol Components

- BlueberryBank
  - Store each position's collateral tokens (in the form of wrapped LP tokens)
  - Users can execute "spells", e.g. opening a new position, closing/adjusting existing position.
- Caster
  - Intermediate contract that just calls another contract function (low-level call) with provided data (instead of bank), to prevent attac.
  - Doesn't store any funds
- Spells (e.g. Ichi,Uniswap/Sushiswap/Curve/...)
  - Define how to interact with each pool
  - Execute `borrow`/`repay` assets by intereacting wtih the bank, which will then interact with the lending protocol.
  
### Component Interaction Flow

1. User -> BlueberryBank.
   User calls `execute` to BlueberryBank, specifying which spell and function to use, e.g. `addLiquidity` using Uniswap spell.
2. BlueberryBank -> Caster
   Forward low-level spell call to Caster (doesn't hold funds), to prevent attacks.
3. Caster -> Spell   
   Caster does low-level call to Spell.
4. Spell may call BlueberryBank to e.g. `doBorrow` funds, `doTransmit` funds from users (so users can approve only the bank, not each spell), `doRepay` debt. Funders are then sent to Spell. to execute pool interaction.   
5. Spells -> Pools   
   Spells interact with Pools (e.g. optimally swap before supplying to Uniswap, or removing liquidity from the pool and pay back some debts).
6. (Optional) Stake LP tokens in wrapper contracts (e.g. WStakingRewards for Uniswap + Balancer).
7. Spell may put collateral back to BlueberryBank.
   If the spell function called is e.g. to open a new position, then the LP tokens will be stored in BlueberryBank.
   
## Example Execution

### AddLiquidity

1. User calls `execute(0, USDT, WETH, data)` on BlueberryBank contract. `data` encodes UniswapSpell function call with arguments (including how much of each asset to supply, to borrow, and slippage control settings).
2. BlueberryBank forwards data call to Caster.
3. Caster does low-level call (with `data`, which encodes `addLiquidity` function call with arguments) to UniswapSpell.
4. UniswapSpell executes `addLiquidityWERC20`
  - `doTransmit` desired amount of assets the user wants to supply
  - `doBorrow` from the lending protocol
  - Optimally swap assets and add liquidity to Uniswap pool
  - Wrap LP tokens to wrapper WERC20 (toget ERC 1155)
  - `doPutCollateral` wrapped tokens back to BlueberryBank
  - Refund leftover assets to the user.
  
>For **Uniswap** pools with staking rewards, use `addLiquidityWStakingRewards` function.
>For **Sushiswap** pools with staking in masterchef, use `addLiquidityWMasterChef` function.
>For **Balancer** pools with staking rewards, use `addLiquidityWStakingRewards` function.
>For all **Curve** pools, use `addLiquidity[N]` (where `N` is the number of underlying tokens). The spell will auto put in Curve's liquidity guage.

## Oracle 

Prices are determined in USD.

- For regular assets, asset prices can be derived from Uniswap pool (with WETH), or Keep3r.
- For LP tokens, asset prices will determine the optimal reserve proportion of the underlying assets, which are then used to compoute the value of LP tokens. See `Uniswapv3AdpaterOracle.sol` for example implementation.
   
