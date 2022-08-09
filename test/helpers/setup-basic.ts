import { BigNumber } from 'ethers';
import { ethers, deployments, upgrades } from 'hardhat';
import { CONTRACT_NAMES } from "../../constants"
import { CoreOracle, HomoraBank, MockERC20, MockWETH, ProxyOracle, SimpleOracle, WERC20 } from '../../typechain-types';

export const setupBasic = deployments.createFixture(async () => {
	const signers = await ethers.getSigners();

	const MockWETH = await ethers.getContractFactory(CONTRACT_NAMES.MockWETH);
	const mockWETH = <MockWETH>await MockWETH.deploy();
	await mockWETH.deployed();

	const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
	const werc20 = <WERC20>await WERC20.deploy();
	await werc20.deployed();

	const MockERC20 = await ethers.getContractFactory(CONTRACT_NAMES.MockERC20);
	const usdt = <MockERC20>await MockERC20.deploy('USDT', 'USDT', 6);
	await usdt.deployed();

	const usdc = <MockERC20>await MockERC20.deploy('USDC', 'USDC', 6);
	await usdc.deployed();

	const dai = <MockERC20>await MockERC20.deploy('DAI', 'DAI', 6);
	await dai.deployed();

	const SimpleOracle = await ethers.getContractFactory(CONTRACT_NAMES.SimpleOracle);
	const simpleOracle = <SimpleOracle>await SimpleOracle.deploy();
	await simpleOracle.deployed();
	await simpleOracle.setETHPx(
		[
			mockWETH.address,
			usdt.address,
			usdc.address,
			dai.address,
		],
		[
			BigNumber.from(2).pow(112),
			BigNumber.from(2).pow(112).mul(BigNumber.from(10).pow(12)).div(600),
			BigNumber.from(2).pow(112).mul(BigNumber.from(10).pow(12)).div(600),
			BigNumber.from(2).pow(112).div(600)
		],
	)

	const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
	const coreOracle = <CoreOracle>await CoreOracle.deploy();
	await coreOracle.deployed();

	const ProxyOracle = await ethers.getContractFactory(CONTRACT_NAMES.ProxyOracle);
	const proxyOracle = <ProxyOracle>await ProxyOracle.deploy(coreOracle.address);
	await proxyOracle.deployed();
	await proxyOracle.setWhitelistERC1155([werc20.address], true);

	const HomoraBank = await ethers.getContractFactory(CONTRACT_NAMES.HomoraBank);
	// const homoraBank = <HomoraBank>await HomoraBank.deploy(proxyOracle.address, 2000);

	const homoraBank = <HomoraBank>await upgrades.deployProxy(HomoraBank,
		[proxyOracle.address, 2000],
		{
			initializer: "initialize",
			unsafeAllow: ['delegatecall']
		}
	)
	await homoraBank.deployed();
	console.log("Oracle Address: ", await homoraBank.oracle());

	const CERC20 = await ethers.getContractFactory(CONTRACT_NAMES.MockCErc20);
	const cerc20 = await CERC20.deploy(mockWETH.address);
	await mockWETH.connect(signers[9]).deposit({ 'value': ethers.utils.parseEther('100') });
	await mockWETH.connect(signers[9]).transfer(cerc20.address, ethers.utils.parseEther('100'));
	await homoraBank.addBank(mockWETH.address, cerc20.address);

	for (const token of [dai, usdt, usdc]) {
		const CERC20 = await ethers.getContractFactory(CONTRACT_NAMES.MockCErc20);
		const cerc20 = await CERC20.deploy(token.address);
		await token.mint(cerc20.address, ethers.utils.parseEther('100'));
		await homoraBank.addBank(token.address, cerc20.address);
	}

	return {
		mockWETH,
		werc20,
		usdt,
		usdc,
		dai,
		simpleOracle,
		coreOracle,
		proxyOracle,
		homoraBank
	}
})