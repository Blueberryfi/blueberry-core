echo "Deploying to Phalcon"

echo "Deploying Blueberry Money Market"

# Deploy Money Market
yarn extract-artifacts --id "20240118-unitroller" --name "Unitroller" --file "Unitroller"
yarn hardhat deploy --network phalcon --id "20240118-unitroller"

sleep 10

yarn extract-artifacts --id "20240118-comptroller" --name "Comptroller" --file "Comptroller"
yarn hardhat deploy --network phalcon --id "20240118-comptroller"
sleep 10

yarn extract-artifacts --id "20240118-jump-rate-model-v2" --name "JumpRateModelV2" --file "JumpRateModelV2"
yarn hardhat deploy --network phalcon --id "20240118-jump-rate-model-v2"
sleep 10

yarn extract-artifacts --id "20240118-bToken-admin" --name "BTokenAdmin" --file "BTokenAdmin"
yarn hardhat deploy --network phalcon --id "20240118-bToken-admin"
sleep 10

echo "Money Market Deployment Complete"
echo "Deploying Blueberry Protocol"
sleep 10

yarn extract-artifacts --id "20240118-aggregator-oracle" --name "AggregatorOracle" --file "AggregatorOracle"
yarn hardhat deploy --network phalcon --id "20240118-aggregator-oracle" 
sleep 10

yarn extract-artifacts --id "20240118-core-oracle" --name "CoreOracle" --file "CoreOracle"
yarn hardhat deploy --network phalcon --id "20240118-core-oracle"
sleep 10

yarn extract-artifacts --id "20240118-uni-v3-wrapped-lib-container" --name "Univ3WrappedLibContainer" --file "Univ3WrappedLibContainer"
yarn hardhat deploy --network phalcon --id "20240118-uni-v3-wrapped-lib-container"
sleep 10

yarn extract-artifacts --id "20240118-uniswap-v3-adapter-oracle" --name "Univ3WrappedLibContainer" --file "Uniswapv3AdapterOracle"
yarn extract-artifacts --id "20240118-uniswap-v3-adapter-oracle" --name "Uniswapv3AdapterOracle" --file "Uniswapv3AdapterOracle"
yarn hardhat deploy --network phalcon --id "20240118-uniswap-v3-adapter-oracle"
sleep 10

yarn extract-artifacts --id "20240118-protocol-config" --name "ProtocolConfig" --file "ProtocolConfig"
yarn hardhat deploy --network phalcon --id "20240118-protocol-config"
sleep 10

yarn extract-artifacts --id "20240118-ichi-vault-oracle" --name "Univ3WrappedLibContainer" --file "IchiVaultOracle"
yarn extract-artifacts --id "20240118-ichi-vault-oracle" --name "IchiVaultOracle" --file "IchiVaultOracle"
yarn hardhat deploy --network phalcon --id "20240118-ichi-vault-oracle"
sleep 10

yarn extract-artifacts --id "20240118-curve-stable-oracle" --name "CurveStableOracle" --file "CurveStableOracle"
yarn hardhat deploy --network phalcon --id "20240118-curve-stable-oracle"
sleep 10

yarn extract-artifacts --id "20240118-curve-tricrypto-oracle" --name "CurveTricryptoOracle" --file "CurveTricryptoOracle"
yarn hardhat deploy --network phalcon --id "20240118-curve-tricrypto-oracle"
sleep 10

yarn extract-artifacts --id "20240118-curve-volatile-oracle" --name "CurveVolatileOracle" --file "CurveVolatileOracle"
yarn hardhat deploy --network phalcon --id "20240118-curve-volatile-oracle"
sleep 10

yarn extract-artifacts --id "20240118-blueberry-bank" --name "BlueberryBank" --file "BlueberryBank"
yarn hardhat deploy --network phalcon --id "20240118-blueberry-bank"
sleep 10

yarn extract-artifacts --id "20240118-hard-vault" --name "HardVault" --file "HardVault"
yarn hardhat deploy --network phalcon --id "20240118-hard-vault"
sleep 10

yarn extract-artifacts --id "20240118-bAlcx-soft-vault" --name "SoftVault" --file "SoftVault"
yarn extract-artifacts --id "20240118-bAlcx-soft-vault" --name "BCollateralCapErc20Delegate" --file "BCollateralCapErc20Delegate"
yarn hardhat deploy --network phalcon --id "20240118-bAlcx"
sleep 10

yarn extract-artifacts --id "20240118-bBal-soft-vault" --name "SoftVault" --file "SoftVault"
yarn extract-artifacts --id "20240118-bBal-soft-vault" --name "BCollateralCapErc20Delegate" --file "BCollateralCapErc20Delegate"
yarn hardhat deploy --network phalcon --id "20240118-bBal"
sleep 10

yarn extract-artifacts --id "20240118-bCrv-soft-vault" --name "SoftVault" --file "SoftVault"
yarn extract-artifacts --id "20240118-bCrv-soft-vault" --name "BCollateralCapErc20Delegate" --file "BCollateralCapErc20Delegate"
yarn hardhat deploy --network phalcon --id "20240118-bCrv"
sleep 10

yarn extract-artifacts --id "20240118-bLink-soft-vault" --name "SoftVault" --file "SoftVault"
yarn extract-artifacts --id "20240118-bLink-soft-vault" --name "BCollateralCapErc20Delegate" --file "BCollateralCapErc20Delegate"
yarn hardhat deploy --network phalcon --id "20240118-bLink"
sleep 10

yarn extract-artifacts --id "20240118-bMim-soft-vault" --name "SoftVault" --file "SoftVault"
yarn extract-artifacts --id "20240118-bMim-soft-vault" --name "BCollateralCapErc20Delegate" --file "BCollateralCapErc20Delegate"
yarn hardhat deploy --network phalcon --id "20240118-bMim"
sleep 10

yarn extract-artifacts --id "20240118-bUsdc-soft-vault" --name "SoftVault" --file "SoftVault"
yarn extract-artifacts --id "20240118-bUsdc-soft-vault" --name "BCollateralCapErc20Delegate" --file "BCollateralCapErc20Delegate"
yarn hardhat deploy --network phalcon --id "20240118-bUsdc"
sleep 10

yarn extract-artifacts --id "20240118-bWbtc-soft-vault" --name "SoftVault" --file "SoftVault"
yarn extract-artifacts --id "20240118-bWbtc-soft-vault" --name "BCollateralCapErc20Delegate" --file "BCollateralCapErc20Delegate"
yarn hardhat deploy --network phalcon --id "20240118-bWbtc"
sleep 10

yarn extract-artifacts --id "20240118-bWeth-soft-vault" --name "SoftVault" --file "SoftVault"
yarn extract-artifacts --id "20240118-bWeth-soft-vault" --name "BCollateralCapErc20Delegate" --file "BCollateralCapErc20Delegate"
yarn hardhat deploy --network phalcon --id "20240118-bWeth"
sleep 10

yarn extract-artifacts --id "20240118-wIchi-farm" --name "WIchiFarm" --file "WIchiFarm"
yarn hardhat deploy --network phalcon --id "20240118-wIchi-farm"
sleep 10

yarn extract-artifacts --id "20240118-wErc20" --name "WERC20" --file "WERC20"
yarn hardhat deploy --network phalcon --id "20240118-wErc20"
sleep 10

yarn extract-artifacts --id "20240118-pool-escrow" --name "PoolEscrowFactory" --file "PoolEscrowFactory"
yarn hardhat deploy --network phalcon --id "20240118-pool-escrow"
sleep 10

yarn extract-artifacts --id "20240118-wAura-booster" --name "WAuraBooster" --file "WAuraBooster"
yarn hardhat deploy --network phalcon --id "20240118-wAura-booster"
sleep 10

yarn extract-artifacts --id "20240118-wConvex-booster" --name "WConvexBooster" --file "WConvexBooster"
yarn hardhat deploy --network phalcon --id "20240118-wConvex-booster"
sleep 10

yarn extract-artifacts --id "20240118-aura-spell" --name "AuraSpell" --file "AuraSpell"
yarn hardhat deploy --network phalcon --id "20240118-aura-spell"
sleep 10

yarn extract-artifacts --id "20240118-aura-spell" --name "AuraSpell" --file "AuraSpell"
yarn hardhat deploy --network phalcon --id "20240118-aura-spell"
sleep 10

yarn extract-artifacts --id "20240118-convex-spell" --name "ConvexSpell" --file "ConvexSpell"
yarn hardhat deploy --network phalcon --id "20240118-convex-spell"
sleep 10

yarn extract-artifacts --id "20240118-short-long-spell" --name "ShortLongSpell" --file "ShortLongSpell"
yarn hardhat deploy --network phalcon --id "20240118-short-long-spell"


# find . -path "*00000000-constants*" -prune -o -path "*/output/phalcon.json" -type f -exec rm -f {} +