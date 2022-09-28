import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { ADDRESS_GOERLI, CONTRACT_NAMES } from '../../../constants';
import { AggregatorOracle, BlueBerryBank, ChainlinkAdapterOracle, CoreOracle, IchiLpOracle, IchiVaultSpell, IICHIVault, MockFeedRegistry, ProxyOracle, SafeBox, UniswapV3AdapterOracle, WERC20, WIchiFarm } from '../../../typechain-types';

async function main(): Promise<void> {
	// Chainlink Adapter Oracle
	const MockFeedRegistry = await ethers.getContractFactory(CONTRACT_NAMES.MockFeedRegistry);
	const feedRegistry = <MockFeedRegistry>await MockFeedRegistry.deploy();
	await feedRegistry.deployed();
	console.log('Chainlink Feed Registry:', feedRegistry.address);
	await feedRegistry.setFeed(
		ADDRESS_GOERLI.SupplyToken,
		ADDRESS_GOERLI.CHAINLINK_USD,
		'0xAb5c49580294Aff77670F839ea425f5b78ab3Ae7' // USDC/USD Data Feed
	);

	const ChainlinkAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracle);
	const chainlinkOracle = <ChainlinkAdapterOracle>await ChainlinkAdapterOracle.deploy(feedRegistry.address);
	await chainlinkOracle.deployed();
	console.log('Chainlink Oracle Address:', chainlinkOracle.address);

	console.log('Setting up USDC config on Chainlink Oracle\nMax Delay Times: 129900s');
	await chainlinkOracle.setMaxDelayTimes([ADDRESS_GOERLI.SupplyToken], [129900]);

	// Aggregator Oracle
	const AggregatorOracle = await ethers.getContractFactory(CONTRACT_NAMES.AggregatorOracle);
	const aggregatorOracle = <AggregatorOracle>await AggregatorOracle.deploy();
	await aggregatorOracle.deployed();

	await aggregatorOracle.setPrimarySources(
		ADDRESS_GOERLI.SupplyToken,
		BigNumber.from(10).pow(16).mul(105), // 5%
		[chainlinkOracle.address]
	);

	// Uni V3 Adapter Oracle
	const UniswapV3AdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.UniswapV3AdapterOracle);
	const uniV3Oracle = <UniswapV3AdapterOracle>await UniswapV3AdapterOracle.deploy(aggregatorOracle.address);
	await uniV3Oracle.deployed();
	console.log('Uni V3 Oracle Address:', uniV3Oracle.address);

	await uniV3Oracle.setPoolsStable([ADDRESS_GOERLI.BaseToken], [ADDRESS_GOERLI.UNI_V3_ICHI_USDC]);
	await uniV3Oracle.setTimeAgos([ADDRESS_GOERLI.BaseToken], [10]); // 10s ago

	// Core Oracle
	const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
	const coreOracle = <CoreOracle>await CoreOracle.deploy();
	await coreOracle.deployed();
	console.log('Core Oracle Address:', coreOracle.address);

	await coreOracle.setRoute(
		[ADDRESS_GOERLI.SupplyToken, ADDRESS_GOERLI.BaseToken],
		[aggregatorOracle.address, uniV3Oracle.address]
	);

	// Ichi Lp Oracle
	const IchiLpOracle = await ethers.getContractFactory(CONTRACT_NAMES.IchiLpOracle);
	const ichiLpOracle = <IchiLpOracle>await IchiLpOracle.deploy(coreOracle.address);
	await ichiLpOracle.deployed();
	console.log('Ichi Lp Oracle Address:', coreOracle.address);

	await coreOracle.setRoute(
		[ADDRESS_GOERLI.ICHI_VAULT_USDC],
		[ichiLpOracle.address]
	);

	// Proxy Oracle
	const ProxyOracle = await ethers.getContractFactory(CONTRACT_NAMES.ProxyOracle);
	const proxyOracle = <ProxyOracle>await ProxyOracle.deploy(coreOracle.address);
	await proxyOracle.deployed();
	console.log('Proxy Oracle Address:', proxyOracle.address);

	// Bank
	const Bank = await ethers.getContractFactory(CONTRACT_NAMES.BlueBerryBank);
	const bank = <BlueBerryBank>await Bank.deploy();
	await bank.deployed();
	await bank.initialize(proxyOracle.address, 2000);
	console.log('Bank:', bank.address);

	// WERC20 of Ichi Vault Lp
	const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
	const werc20 = <WERC20>await WERC20.deploy();
	await werc20.deployed();
	console.log('WERC20:', werc20.address);

	// WIchiFarm
	const WIchiFarm = await ethers.getContractFactory(CONTRACT_NAMES.WIchiFarm);
	const wichiFarm = <WIchiFarm>await WIchiFarm.deploy(ADDRESS_GOERLI.BaseToken, ethers.constants.AddressZero);
	await wichiFarm.deployed();
	console.log('WIchiFarm:', wichiFarm.address);

	// Ichi Vault Spell
	const IchiVaultSpell = await ethers.getContractFactory(CONTRACT_NAMES.IchiVaultSpell);
	const ichiSpell = <IchiVaultSpell>await IchiVaultSpell.deploy(
		bank.address,
		werc20.address,
		ADDRESS_GOERLI.WETH,
		wichiFarm.address
	)
	await ichiSpell.deployed();
	console.log('Ichi Spell:', ichiSpell.address);

	// SafeBox
	const SafeBox = await ethers.getContractFactory(CONTRACT_NAMES.SafeBox);
	const safeBox = <SafeBox>await SafeBox.deploy(
		ADDRESS_GOERLI.SupplyToken,
		"Interest Bearing USDC",
		"ibUSDC"
	)
	await safeBox.deployed();
	console.log('SafeBox:', safeBox.address);

	// Add Bank
	await bank.addBank(
		ADDRESS_GOERLI.SupplyToken,
		ADDRESS_GOERLI.bSupplyToken,
		safeBox.address
	)
}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
