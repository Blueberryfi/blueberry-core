import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from '../../constants';
import { AggregatorOracle, BandAdapterOracle, ChainlinkAdapterOracle } from '../../typechain-types';

async function main(): Promise<void> {
	// Band Adapter Oracle
	const BandAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.BandAdapterOracle);
	const bandOracle = <BandAdapterOracle>await BandAdapterOracle.deploy(ADDRESS.BandStdRef);
	await bandOracle.deployed();
	console.log("Band Oracle Address:", bandOracle.address);

	console.log('Setting up USDC config on Band Oracle\nMax Delay Times: 11100s, Symbol: USDC');
	await bandOracle.setMaxDelayTimes([ADDRESS.USDC], [11100]);
	await bandOracle.setSymbols([ADDRESS.USDC], ['USDC']);

	// Chainlink Adapter Oracle
	const ChainlinkAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracle);
	const chainlinkOracle = <ChainlinkAdapterOracle>await ChainlinkAdapterOracle.deploy(ADDRESS.ChainlinkRegistry);
	await chainlinkOracle.deployed();
	console.log('Chainlink Oracle Address:', chainlinkOracle.address);

	console.log('Setting up USDC config on Chainlink Oracle\nMax Delay Times: 129900s');
	await chainlinkOracle.setMaxDelayTimes([ADDRESS.USDC], [129900]);

	// Aggregator Oracle
	const AggregatorOracle = await ethers.getContractFactory(CONTRACT_NAMES.AggregatorOracle);
	const aggregatorOracle = <AggregatorOracle>await AggregatorOracle.deploy();
	await aggregatorOracle.deployed();

	await aggregatorOracle.setPrimarySources(
		ADDRESS.USDC,
		BigNumber.from(10).pow(16).mul(105), // 5%
		[bandOracle.address, chainlinkOracle.address]
	);


}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
