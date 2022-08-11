import { BigNumber } from 'ethers';
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
		ADDRESS.BAL_PERP_USDC_8020,				// underlying - Balancer PERP/USDC Pool (80/20)
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
	const uniOracle = <UniswapV2Oracle>await UniswapV2Oracle.deploy(coreOracle.address);
	await uniOracle.deployed();
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

	// Setup Oracles
	await coreOracle.setRoute([
		ADDRESS.ETH, ADDRESS.WETH, ADDRESS.DAI,
		ADDRESS.USDC, ADDRESS.USDT, ADDRESS.WBTC,
		ADDRESS.DPI, ADDRESS.PERP, ADDRESS.SNX,
		ADDRESS.UNI_V2_DAI_WETH, ADDRESS.UNI_V2_USDT_WETH, ADDRESS.UNI_V2_USDC_WETH,
		ADDRESS.UNI_V2_WBTC_WETH, ADDRESS.UNI_V2_DPI_WETH, ADDRESS.SUSHI_WETH_USDT,
		ADDRESS.BAL_WETH_DAI_8020, ADDRESS.BAL_PERP_USDC_8020, ADDRESS.CRV_3_POOL,
	], [
		keeperOracle.address,
		keeperOracle.address,
		keeperOracle.address,
		keeperOracle.address,
		keeperOracle.address,
		keeperOracle.address,
		keeperOracle.address,
		keeperOracle.address,
		keeperOracle.address,
		uniOracle.address,
		uniOracle.address,
		uniOracle.address,
		uniOracle.address,
		uniOracle.address,
		uniOracle.address,
		uniOracle.address,
		uniOracle.address,
		uniOracle.address,
	])
	await proxyOracle.setTokenFactors([
		ADDRESS.WETH, ADDRESS.DAI, ADDRESS.USDC, ADDRESS.USDT,
		ADDRESS.WBTC, ADDRESS.DPI, ADDRESS.PERP, ADDRESS.SNX,
		ADDRESS.UNI_V2_DAI_WETH, ADDRESS.UNI_V2_USDT_WETH,
		ADDRESS.UNI_V2_USDC_WETH, ADDRESS.UNI_V2_WBTC_WETH,
		ADDRESS.UNI_V2_DPI_WETH, ADDRESS.SUSHI_WETH_USDT,
		ADDRESS.BAL_WETH_DAI_8020, ADDRESS.BAL_PERP_USDC_8020,
		ADDRESS.CRV_3_POOL
	], [
		{
			borrowFactor: 12500,
			collateralFactor: 8000,
			liqIncentive: 10250,
		}, {
			borrowFactor: 10500,
			collateralFactor: 9500,
			liqIncentive: 10250,
		}, {
			borrowFactor: 10500,
			collateralFactor: 9500,
			liqIncentive: 10250,
		}, {
			borrowFactor: 10500,
			collateralFactor: 9500,
			liqIncentive: 10250,
		}, {
			borrowFactor: 12500,
			collateralFactor: 8000,
			liqIncentive: 10250,
		}, {
			borrowFactor: 50000,
			collateralFactor: 0,
			liqIncentive: 10250,
		}, {
			borrowFactor: 50000,
			collateralFactor: 0,
			liqIncentive: 10250,
		}, {
			borrowFactor: 50000,
			collateralFactor: 0,
			liqIncentive: 10250,
		}, {
			borrowFactor: 50000,
			collateralFactor: 8000,
			liqIncentive: 10250,
		}, {
			borrowFactor: 50000,
			collateralFactor: 8000,
			liqIncentive: 10250,
		}, {
			borrowFactor: 50000,
			collateralFactor: 8000,
			liqIncentive: 10250,
		}, {
			borrowFactor: 50000,
			collateralFactor: 8000,
			liqIncentive: 10250,
		}, {
			borrowFactor: 50000,
			collateralFactor: 8000,
			liqIncentive: 10250,
		}, {
			borrowFactor: 50000,
			collateralFactor: 8000,
			liqIncentive: 10250,
		}, {
			borrowFactor: 50000,
			collateralFactor: 8000,
			liqIncentive: 10250,
		}, {
			borrowFactor: 50000,
			collateralFactor: 0,
			liqIncentive: 10250,
		}, {
			borrowFactor: 50000,
			collateralFactor: 9500,
			liqIncentive: 10250,
		}
	])
	await proxyOracle.setWhitelistERC1155([
		werc20.address,
		wmas.address,
		wliq.address,
		wsindex.address,
		wsperp.address
	], true);

	//========== Deploy Bank Contracts ==========//
	const HomoraBank = await ethers.getContractFactory(CONTRACT_NAMES.HomoraBank);
	const homoraBank = await upgrades.deployProxy(HomoraBank, [
		proxyOracle.address, 2000
	])

	//========== Deploy Spell Contracts ==========//
	// UniswapV2SpellV1
	const UniswapV2SpellV1 = await ethers.getContractFactory(CONTRACT_NAMES.UniswapV2SpellV1);
	const uniSpell = await UniswapV2SpellV1.deploy(
		homoraBank.address, werc20.address, ADDRESS.UNI_V2_ROUTER
	)
	await uniSpell.deployed();
	// SushiswapSpellV1
	const SushiswapSpellV1 = await ethers.getContractFactory(CONTRACT_NAMES.SushiswapSpellV1);
	const sushiSpell = await SushiswapSpellV1.deploy(
		homoraBank.address, werc20.address, ADDRESS.SUSHI_ROUTER
	);
	await sushiSpell.deployed();
	// BalancerSpellV1
	const BalancerSpellV1 = await ethers.getContractFactory(CONTRACT_NAMES.BalancerSpellV1);
	const balSpell = await BalancerSpellV1.deploy(
		homoraBank.address, werc20.address, ADDRESS.WETH
	);
	await balSpell.deployed();
	// CurveSpellV1
	const CurveSpellV1 = await ethers.getContractFactory(CONTRACT_NAMES.CurveSpellV1);
	const crvSpell = await CurveSpellV1.deploy(
		homoraBank.address, werc20.address, ADDRESS.WETH
	);
	await crvSpell.deployed();
	await crvOracle.registerPool(ADDRESS.CRV_3_POOL);
}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
