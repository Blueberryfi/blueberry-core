# blueberry-core v1 

## Protocol Summary

Blueberry Core v1 is a leveraged yield-farming product. 
Additional documentation can be found [here](https://docs.blueberry.garden/).
Here are some key features:

The protocol is integrated with an existing lending protocol (Blueberry Money Market). Whenever a user wants to borrow funds (on leverage) to yield farm additionally, Blueberry Bank will borrow from the lending protocol (Blueberry Money Market).

- A wide variety of assets are borrowable, including stables like USDC, USDT, and DAI.
- Each "spell" defines how the protocol interacts with the end deployment. Such as concentrated liquidity vaults, e.g. Ichi vault.
  - Spell functions include e.g. `_deposit`, `_withdraw`.
- Adjustable positions - users can adjust their existing positions by supplying more assets (Isolated collateral), borrowing more assets, or repaying some debts.
  - As long as the collateral credit (Deployment + Isolated Collateral value) >= borrow credit. Otherwise, the position is at liquidation risk.
  
## Protocol Components

- BlueberryBank
  - Store each position's collateral tokens (in the form of wrapped NFT tokens)
  - Users can execute "spells", e.g. opening a new position or closing/adjusting an existing position.
- Spells (e.g. Ichi, Uniswap/Aura/Convex/...)
  - Define how to interact with each external protocol
  - Execute `borrow`/`repay` assets by interacting with the bank, which will then interact with the lending protocol (Blueberry Money Market).
  
### Component Interaction Flow

1. User -> BlueberryBank.
   User calls `execute` to BlueberryBank, specifying which spell and function to use, e.g. `_deposit using IchiSpell.
2. BlueberryBank -> Spell
3. Spell may call BlueberryBank to e.g. `_doBorrow` funds and `_doRepay` debt. Funders are then sent to Spell. to execute pool interaction.   
4. Spells -> Pools   
   Spells interact with Pools (e.g. optimally swap before supplying to Uniswap, or remove liquidity from the pool and pay back some debts).
5. (Optional) Stake LP tokens in wrapper contracts (e.g. WStakingRewards for Uniswap + Balancer).
6. Spell may put collateral back to BlueberryBank.
   If the spell function called is e.g. to open a new position, then the LP tokens will be stored in BlueberryBank.
   
## Example Execution

### putCollateral

1. User calls `execute(0, USDT, WETH, data)` on BlueberryBank contract. `data` encodes IchiSpell function call with arguments (including how much of each asset to supply, to borrow, and slippage control settings).
2. BlueberryBank uses data calls to encode `putCollateral` function call with arguments to IchiSpell.
3. IchiSpell executes `putCollateralWERC20`
  - `_doBorrow` from the lending protocol
  - Deposit a Single asset into the ICHI vault and receive LP Token
  - Wrap LP tokens to wrapper WERC20 (to get ERC 1155)
  - `_doPutCollateral` wrapped tokens back to BlueberryBank
  - Refund leftover assets to the user.
  
<!---  >For **Uniswap** pools with staking rewards, use `putCollateralWStakingRewards` function.
>For **Sushiswap** pools with staking in masterchef, use `putCollateralWMasterChef` function.
>For **Balancer** pools with staking rewards, use `putCollateralWStakingRewards` function.
>For all **Curve** pools, use `putCollateral[N]` (where `N` is the number of underlying tokens). The spell will auto put in Curve's liquidity guage. --->

## Oracle 

Prices are determined in USD.

- For regular assets, asset prices can be derived from Chainlink, Band, or Uniswap feeds.
- For LP tokens, asset prices will determine the optimal reserve proportion of the underlying assets, which are then used to compute the value of LP tokens. See `Uniswapv3AdpaterOracle.sol` for an example implementation.
   
## Getting Started

Steps to run the tests:
Hardhat version 2.12.4 Block height 17089048 Eth mainnet fork

Copy all the files
> Clone the repo
### Installs all of the files
> yarn install
### Required for tests and all other actions to work  
> Create .env file with env var DEPLOY_ACCOUNT_KEY= , 
ETHERSCAN_API_KEY=

> If needed update the RPC provider in `hardhat.config.js`  and `/test/helpers/index.js` to your own provider. Currently set to ankr mainnet node.

### Compiles all of the contracts
> yarn hardhat compile

### Runs all of the tests
> yarn hardhat test

### Displays the coverage of the contracts
> yarn hardhat coverage

### Runs the foundry tests

> forge test