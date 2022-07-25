import { loadFixture } from 'ethereum-waffle';
import { Contract } from 'ethers';
import { ethers, deployments, getNamedAccounts } from 'hardhat';
import { CONTRACT_NAMES } from "../constants"

interface Fixture {
	mockWETH: Contract,
	werc20: Contract,
	usdt: Contract,
	usdc: Contract,
	dai: Contract,
	simpleOracle: Contract,
	coreOracle: Contract,
	proxyOracle: Contract,
}

describe("test", () => {
	let fixture: Fixture;
	async function deployFixture(): Promise<Fixture> {
		const signers = await ethers.getSigners();
		// fixture tag: "function"
		const MockWETH = await ethers.getContractFactory(CONTRACT_NAMES.MockETH);
		const mockWETH = await MockWETH.deploy();
		await mockWETH.deployed();

		const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
		const werc20 = await WERC20.deploy();
		await werc20.deployed();

		const MockERC20 = await ethers.getContractFactory(CONTRACT_NAMES.MockERC20);
		const usdt = await MockERC20.deploy('USDT', 'USDT', 6);
		await usdt.deployed();

		const usdc = await MockERC20.deploy('USDC', 'USDC', 6);
		await usdc.deployed();

		const dai = await MockERC20.deploy('DAI', 'DAI', 6);
		await dai.deployed();

		const SimpleOracle = await ethers.getContractFactory(CONTRACT_NAMES.SimpleOracle);
		const simpleOracle = await SimpleOracle.deploy();
		await simpleOracle.deployed();
		await simpleOracle.setETHPx(
			[
				mockWETH.address,
				usdt.address,
				usdc.address,
				dai.address,
			],
			[
				2 ** 112,
				Math.floor(2 ** 112 * 10 ** 12 / 600),
				Math.floor(2 ** 112 * 10 ** 12 / 600),
				Math.floor(2 ** 112 / 600)
			],
		)

		const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
		const coreOracle = await CoreOracle.deploy();
		await coreOracle.deployed();

		const ProxyOracle = await ethers.getContractFactory(CONTRACT_NAMES.ProxyOracle);
		const proxyOracle = await ProxyOracle.deploy(coreOracle.address);
		await proxyOracle.deployed();
		await proxyOracle.setWhitelistERC1155([werc20.address], true);

		const HomoraBank = await ethers.getContractFactory(CONTRACT_NAMES.HomoraBank);
		const homoraBank = await HomoraBank.deploy();
		await homoraBank.initialize(oracle.address, 2000);

		for (const token of [mockWETH, dai, usdt, usdc]) {
			const CERC20 = await ethers.getContractFactory(CONTRACT_NAMES.MockCErc20);
			const cerc20 = await CERC20.deploy(token.address);
			if (token === mockWETH) {
				await mockWETH.connect(signers[9]).deposit({ 'value': '100000 ether' });
				await mockWETH.transfer(cerc20.address, ethers.utils.parseEther('100000'));
			} else {
				await token.mint(cerc20.address, ethers.utils.parseEther('100000'));
			}
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
		}
	}
	beforeEach(async function () {
		fixture = await loadFixture(deployFixture);
	})
	it('test', async () => {
		console.log(fixture.mockWETH.address);
	})
})