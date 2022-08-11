import { BigNumber, constants } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from '../../constants';
import { BalancerPairOracle, CoreOracle, CurveOracle, ERC20KP3ROracle, HomoraBank, ProxyOracle, UniswapV2Oracle } from '../../typechain-types';

async function main(): Promise<void> {
	//========== Deploy Wrapper Contracts ==========//
	// WERC20
	const WERC20Factory = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
	const werc20 = await WERC20Factory.deploy();
	// WMasterChef - Sushiswap
	const WMasterChef = await ethers.getContractFactory(CONTRACT_NAMES.WMasterChef);
	const wmas = await WMasterChef.deploy(ADDRESS.SUSHI_MASTERCHEF);
	// WLiquidityGauge - Curve Finance
	const WLiquidityGauge = await ethers.getContractFactory(CONTRACT_NAMES.WLiquidityGauge);
	const wliq = await WLiquidityGauge.deploy(ADDRESS.CRV_GAUGE);
	// WStakingRewards - Uniswap
	const WStakingRewards = await ethers.getContractFactory(CONTRACT_NAMES.WStakingRewards);
	const wsindex = await WStakingRewards.deploy(
		ADDRESS.IC_DPI_STAKING_REWARDS, // staking - Index Coop: DPI Staking rewards v2
		ADDRESS.UNI_V2_DPI_WETH, 				// underlying - DPI/WETH Uni v2 pair
		ADDRESS.INDEX, 									// reward - $INDEX token
	)
	const wsperp = await WStakingRewards.deploy(
		ADDRESS.PERP_BALANCER_LP_REWARDS,	// staking - Perpetual Protocol - Balancer LP Rewards
		ADDRESS.BAL_PERP_USDC_POOL,				// underlying - Balancer PERP/USDC Pool (80/20)
		ADDRESS.PERP											// reward - $PERP token
	)

	//========== Deploy Oracle Contracts ==========//
	// ERC20KP3ROracle
	const ERC20KP3ROracle = await ethers.getContractFactory(CONTRACT_NAMES.ERC20KP3ROracle);
	const keeperOracle = <ERC20KP3ROracle>await ERC20KP3ROracle.deploy(ADDRESS.Keep3rV1Oracle);
	await keeperOracle.deployed();
	// CoreOracle
	const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
	const coreOracle = <CoreOracle>await CoreOracle.deploy();
	await coreOracle.deployed();
	// UniswapV2Oracle
	const UniswapV2Oracle = await ethers.getContractFactory(CONTRACT_NAMES.UniswapV2Oracle);
	const lpOracle = <UniswapV2Oracle>await UniswapV2Oracle.deploy(coreOracle.address);
	await lpOracle.deployed();
	// BalancerPairOracle
	const BalancerPairOracle = await ethers.getContractFactory(CONTRACT_NAMES.BalancerPairOracle);
	const balOracle = <BalancerPairOracle>await BalancerPairOracle.deploy(coreOracle.address);
	await balOracle.deployed();
	// CRV Oracle
	const CurveOracle = await ethers.getContractFactory(CONTRACT_NAMES.CurveOracle);
	const crvOracle = <CurveOracle>await CurveOracle.deploy(coreOracle.address);
	await crvOracle.deployed();
	// Proxy Oracle
	const ProxyOracle = await ethers.getContractFactory(CONTRACT_NAMES.ProxyOracle);
	const proxyOracle = <ProxyOracle>await ProxyOracle.deploy(coreOracle.address);
	await proxyOracle.deployed();

}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
