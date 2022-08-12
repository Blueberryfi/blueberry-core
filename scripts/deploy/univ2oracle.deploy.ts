import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from '../../constants';
import { CoreOracle, ERC20KP3ROracle, ProxyOracle, UniswapV2Oracle } from '../../typechain-types';

const deployUniV2Oracles = async () => {
	// Deploy Uniswap V2 Oracle
	const ERC20KP3ROracle = await ethers.getContractFactory(CONTRACT_NAMES.ERC20KP3ROracle);
	const keeperOracle = <ERC20KP3ROracle>await ERC20KP3ROracle.deploy(ADDRESS.Keep3rV1Oracle);
	await keeperOracle.deployed();

	const UniswapV2Oracle = await ethers.getContractFactory(CONTRACT_NAMES.UniswapV2Oracle);
	const lpOracle = <UniswapV2Oracle>await UniswapV2Oracle.deploy(keeperOracle.address);
	await lpOracle.deployed();

	console.log(`ERC20KP3ROracle: ${keeperOracle.address}`);
	console.log(`UniswapV2Oracle: ${lpOracle.address}`);

	let price = await keeperOracle.getETHPx(ADDRESS.USDT);
	console.log('USDT Price:', price, BigNumber.from(2).pow(112).div(price));

	price = await keeperOracle.getETHPx(ADDRESS.USDC);
	console.log('USDC Price:', price, BigNumber.from(2).pow(112).div(price));

	price = await lpOracle.getETHPx(ADDRESS.UNI_V2_USDT_USDC);
	console.log('USDC/USDT Uni V2 Lp Price:', price, BigNumber.from(2).pow(112).div(price));
}

const deployCoreOracles = async () => {
	const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
	const coreOracle = <CoreOracle>await CoreOracle.deploy();
	await coreOracle.deployed();
	console.log('CoreOracle Address', coreOracle.address);

	const ProxyOracle = await ethers.getContractFactory(CONTRACT_NAMES.ProxyOracle);
	const proxyOracle = <ProxyOracle>await ProxyOracle.deploy(coreOracle.address);
	await proxyOracle.deployed();
	console.log('ProxyOracle Address', proxyOracle.address);
}

async function main(): Promise<void> {
	await deployUniV2Oracles();
	await deployCoreOracles();
}

main()
	.then(() => process.exit(0))
	.catch((error: Error) => {
		console.error(error);
		process.exit(1);
	});
