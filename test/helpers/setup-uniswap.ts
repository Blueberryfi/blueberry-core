import { ethers, deployments } from 'hardhat';
import { CONTRACT_NAMES } from "../../constants"
import { MockUniswapV2Factory, MockUniswapV2Router02, MockWETH } from '../../typechain-types';

export const setupUniswap = deployments.createFixture(async () => {
	const signers = await ethers.getSigners();

	const MockWETH = await ethers.getContractFactory(CONTRACT_NAMES.MockWETH);
	const mockWETH = <MockWETH>await MockWETH.deploy();
	await mockWETH.deployed();

	const MockUniV2Factory = await ethers.getContractFactory(CONTRACT_NAMES.MockUniswapV2Factory);
	const mockUniV2Factory = <MockUniswapV2Factory>await MockUniV2Factory.deploy(signers[0].address);
	await mockUniV2Factory.deployed();

	const MockUniV2Router02 = await ethers.getContractFactory(CONTRACT_NAMES.MockUniswapV2Router02);
	const mockUniV2Router02 = <MockUniswapV2Router02>await MockUniV2Router02.deploy(mockUniV2Factory.address, mockWETH.address);
	await mockUniV2Router02.deployed();

	return {
		mockWETH,
		mockUniV2Factory,
		mockUniV2Router02,
	}
})