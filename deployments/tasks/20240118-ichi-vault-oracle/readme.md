# 2024-01-18 IchiVaultOracle

The logic of this oracle is using legacy & traditional mathematics of Uniswap V2 Lp Oracle. Base token prices are fetched from Chainlink or Band Protocol. To prevent flashloan price manipulations, it compares spot & twap prices from Uni V3 Pool.

## Useful Links
- [Docs](https://docs.blueberry.garden/developer-guides/contracts/oracle/introduction)

## Useful Files

- [Ethereum mainnet addresses](./output/mainnet.json)
- [Sepolia testnet addresses](./output/sepolia.json)
- [Phalcon devnet addresses](./output/phalcon.json)
