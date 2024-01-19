echo "Deploying to Phalcon"

echo "Deploying Blueberry Money Market"

# Deploy Money Market
yarn extract-artifacts --id "20240118-unitroller" --name "Unitroller" --file "Unitroller"
yarn hardhat deploy --network phalcon --id "20240118-unitroller"

yarn extract-artifacts --id "20240118-comptroller" --name "Comptroller" --file "Comptroller"
yarn hardhat deploy --network phalcon --id "20240118-comptroller"

yarn extract-artifacts --id "20240118-jump-rate-model-v2" --name "JumpRateModelV2" --file "JumpRateModelV2"
yarn hardhat deploy --network phalcon --id "20240118-jump-rate-model-v2"

yarn extract-artifacts --id "20240118-bToken-admin" --name "BTokenAdmin" --file "BTokenAdmin"
yarn hardhat deploy --network phalcon --id "20240118-bToken-admin"

echo "Money Market Deployment Complete"
echo "Deploying Blueberry Protocol"

yarn extract-artifacts --id "20240118-aggregator-oracle" --name "AggregatorOracle" --file "AggregatorOracle"
yarn hardhat deploy --network phalcon --id "20240118-aggregator-oracle" 

yarn extract-artifacts --id "20240118-core-oracle" --name "CoreOracle" --file "CoreOracle"
yarn hardhat deploy --network phalcon --id "20240118-core-oracle"

yarn extract-artifacts --id "20240118-uniswap-v3-adapter-oracle" --name "UniswapV3AdapterOracle" --file "UniswapV3AdapterOracle"
yarn hardhat deploy --network phalcon --id "20240118-uniswap-v3-adapter-oracle"

yarn extract-artifacts --id "20240118-protocol-config" --name "ProtocolConfig" --file "ProtocolConfig"
yarn hardhat deploy --network phalcon --id "20240118-protocol-config"

yarn extract-artifacts --id "20240118-ichi-vault-oracle" --name "UniswapV3WrappedLibContainer" --file "UniswapV3WrappedLibContainer"
yarn extract-artifacts --id "20240118-ichi-vault-oracle" --name "IchiVaultOracle" --file "IchiVaultOracle"
yarn hardhat deploy --network phalcon --id "20240118-ichi-vault-oracle"

yarn extract-artifacts --id "20240118-curve-stable-oracle" --name "CurveStableOracle" --file "CurveStableOracle"
yarn hardhat deploy --network phalcon --id "20240118-curve-stable-oracle"

yarn extract-artifacts --id "20240118-curve-tricrypto-oracle" --name "CurveTricryptoOracle" --file "CurveTricryptoOracle"
yarn hardhat deploy --network phalcon --id "20240118-curve-tricrypto-oracle"

yarn extract-artifacts --id "20240118-curve-volatile-oracle" --name "CurveVolatileOracle" --file "CurveVolatileOracle"
yarn hardhat deploy --network phalcon --id "20240118-curve-volatile-oracle"

yarn extract-artifacts --id "20240118-blueberry-bank" --name "BlueberryBank" --file "BlueberryBank"
yarn hardhat deploy --network phalcon --id "20240118-blueberry-bank"

yarn extract-artifacts --id "20240118-hard-vault" --name "HardVault" --file "HardVault"
yarn hardhat deploy --network phalcon --id "20240118-hard-vault"

yarn extract-artifacts --id "20240118-bAlcx-soft-vault" --name "SoftVault" --file "SoftVault"
yarn extract-artifacts --id "20240118-bAlcx-soft-vault" --name "BCollateralCapErc20Delegate" --file "BCollateralCapErc20Delegate"
yarn hardhat deploy --network phalcon --id "20240118-bAlcx"

yarn extract-artifacts --id "20240118-bBal-soft-vault" --name "SoftVault" --file "SoftVault"
yarn extract-artifacts --id "20240118-bBal-soft-vault" --name "BCollateralCapErc20Delegate" --file "BCollateralCapErc20Delegate"
yarn hardhat deploy --network phalcon --id "20240118-bBal"

yarn extract-artifacts --id "20240118-bCrv-soft-vault" --name "SoftVault" --file "SoftVault"
yarn extract-artifacts --id "20240118-bCrv-soft-vault" --name "BCollateralCapErc20Delegate" --file "BCollateralCapErc20Delegate"
yarn hardhat deploy --network phalcon --id "20240118-bCrv"

yarn extract-artifacts --id "20240118-bLink-soft-vault" --name "SoftVault" --file "SoftVault"
yarn extract-artifacts --id "20240118-bLink-soft-vault" --name "BCollateralCapErc20Delegate" --file "BCollateralCapErc20Delegate"
yarn hardhat deploy --network phalcon --id "20240118-bLink"

yarn extract-artifacts --id "20240118-bMim-soft-vault" --name "SoftVault" --file "SoftVault"
yarn extract-artifacts --id "20240118-bMim-soft-vault" --name "BCollateralCapErc20Delegate" --file "BCollateralCapErc20Delegate"
yarn hardhat deploy --network phalcon --id "20240118-bMim"

yarn extract-artifacts --id "20240118-bUsdc-soft-vault" --name "SoftVault" --file "SoftVault"
yarn extract-artifacts --id "20240118-bUsdc-soft-vault" --name "BCollateralCapErc20Delegate" --file "BCollateralCapErc20Delegate"
yarn hardhat deploy --network phalcon --id "20240118-bUsdc"

yarn extract-artifacts --id "20240118-bUsdc-soft-vault" --name "SoftVault" --file "SoftVault"
yarn extract-artifacts --id "20240118-bUsdc-soft-vault" --name "BCollateralCapErc20Delegate" --file "BCollateralCapErc20Delegate"
yarn hardhat deploy --network phalcon --id "20240118-bUsdc"

yarn extract-artifacts --id "20240118-bWbtc-soft-vault" --name "SoftVault" --file "SoftVault"
yarn extract-artifacts --id "20240118-bWbtc-soft-vault" --name "BCollateralCapErc20Delegate" --file "BCollateralCapErc20Delegate"
yarn hardhat deploy --network phalcon --id "20240118-bWbtc"

yarn extract-artifacts --id "20240118-bWeth-soft-vault" --name "SoftVault" --file "SoftVault"
yarn extract-artifacts --id "20240118-bWeth-soft-vault" --name "BCollateralCapErc20Delegate" --file "BCollateralCapErc20Delegate"
yarn hardhat deploy --network phalcon --id "20240118-bWeth"

yarn extract-artifacts --id "20240118-wIchi-farm" --name "WIchiFarm" --file "WIchiFarm"
yarn hardhat deploy --network phalcon --id "20240118-wIchi-farm"

yarn extract-artifacts --id "20240118-wErc20" --name "WERC20" --file "WERC20"
yarn hardhat deploy --network phalcon --id "20240118-wErc20"

yarn extract-artifacts --id "20240118-pool-escrow" --name "PoolEscrowFactory" --file "PoolEscrowFactory"
yarn hardhat deploy --network phalcon --id "20240118-pool-escrow"

yarn extract-artifacts --id "20240118-wAura-booster" --name "WAuraBooster" --file "WAuraBooster"
yarn hardhat deploy --network phalcon --id "20240118-wAura-booster"

yarn extract-artifacts --id "20240118-wConvex-booster" --name "WConvexBooster" --file "WConvexBooster"
yarn hardhat deploy --network phalcon --id "20240118-wConvex-booster"

yarn extract-artifacts --id "20240118-aura-spell" --name "AuraSpell" --file "AuraSpell"
yarn hardhat deploy --network phalcon --id "20240118-aura-spell"

yarn extract-artifacts --id "20240118-aura-spell" --name "AuraSpell" --file "AuraSpell"
yarn hardhat deploy --network phalcon --id "20240118-aura-spell"

yarn extract-artifacts --id "20240118-convex-spell" --name "ConvexSpell" --file "ConvexSpell"
yarn hardhat deploy --network phalcon --id "20240118-convex-spell"

yarn extract-artifacts --id "20240118-short-long-spell" --name "ShortLongSpell" --file "ShortLongSpell"
yarn hardhat deploy --network phalcon --id "20240118-short-long-spell"

