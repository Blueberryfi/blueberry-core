import { ethers, deployments } from 'hardhat';
import { CONTRACT_NAMES } from "../../constants"
import { MockCErc202, MockERC20, MockWETH, SafeBox, SafeBoxETH } from '../../typechain';

export const setupSafeBox = deployments.createFixture(async () => {
	const MockERC20 = await ethers.getContractFactory(CONTRACT_NAMES.MockERC20);
	const mockERC20 = <MockERC20>await MockERC20.deploy('token', "TOKEN", 18);
	await mockERC20.deployed();

	const MockCERC20 = await ethers.getContractFactory(CONTRACT_NAMES.MockCErc20_2);
	const cToken = <MockCErc202>await MockCERC20.deploy(mockERC20.address);
	await cToken.deployed();

	const SafeBox = await ethers.getContractFactory(CONTRACT_NAMES.SafeBox);
	const safeBox = <SafeBox>await SafeBox.deploy(cToken.address, "ibToken", "ibTOKEN");
	await safeBox.deployed();

	const MockWETH = await ethers.getContractFactory(CONTRACT_NAMES.MockWETH);
	const mockWETH = <MockWETH>await MockWETH.deploy();
	await mockWETH.deployed();

	const cWeth = <MockCErc202>await MockCERC20.deploy(mockWETH.address);
	await cWeth.deployed();

	const SafeBoxEth = await ethers.getContractFactory(CONTRACT_NAMES.SafeBoxETH);
	const safeBoxEth = <SafeBoxETH>await SafeBoxEth.deploy(cWeth.address, "ibEther", "ibETH");
	await safeBoxEth.deployed();

	return {
		mockERC20,
		mockWETH,
		cToken,
		cWeth,
		safeBox,
		safeBoxEth
	}
})