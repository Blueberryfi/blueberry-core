import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from '../../constants';
import { ERC20KP3ROracle, UniswapV2Oracle } from '../../typechain-types';

async function main(): Promise<void> {
	// Deploy Uniswap V2 Oracle
	const ERC20KP3ROracle = await ethers.getContractFactory(CONTRACT_NAMES.ERC20KP3ROracle);
	const keeperOracle = <ERC20KP3ROracle>await ERC20KP3ROracle.deploy(ADDRESS.Keep3rV1Oracle);
	await keeperOracle.deployed();

	const UniswapV2Oracle = await ethers.getContractFactory(CONTRACT_NAMES.UniswapV2Oracle);
	const lpOracle = <UniswapV2Oracle>await UniswapV2Oracle.deploy(keeperOracle.address);
	await lpOracle.deployed();

	console.log(`ERC20KP3ROracle: ${keeperOracle.address}`);
	console.log(`UniswapV2Oracle: ${lpOracle.address}`);

	let price = await keeperOracle.getPrice(ADDRESS.USDT);
	console.log('USDT Price:', price, BigNumber.from(2).pow(112).div(price));

	price = await keeperOracle.getPrice(ADDRESS.USDC);
	console.log('USDC Price:', price, BigNumber.from(2).pow(112).div(price));

	price = await lpOracle.getPrice(ADDRESS.UNI_V2_USDT_USDC);
	console.log('USDC/USDT Uni V2 Lp Price:', price, BigNumber.from(2).pow(112).div(price));
}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
