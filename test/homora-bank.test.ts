import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { CONTRACT_NAMES } from "../constants"
import { CoreOracle, ERC20, HomoraBank, MockERC20, MockUniswapV2Factory, MockUniswapV2Router02, MockWETH, SimpleOracle, WERC20 } from '../typechain';
import { execute_uniswap_werc20, setup_uniswap } from './helpers/helper-uniswap';
import { setupBasic } from './helpers/setup-basic';
import { setupUniswap } from './helpers/setup-uniswap';

describe("Homora Bank", () => {
	let admin: SignerWithAddress;
	let alice: SignerWithAddress;
	let bob: SignerWithAddress;
	let eve: SignerWithAddress;

	before(async () => {
		[admin, alice, bob, eve] = await ethers.getSigners();
	})
	describe("Uniswap", () => {
		let bank: HomoraBank;
		let werc20: WERC20;
		let uniV2Router02: MockUniswapV2Router02;
		let uniV2Factory: MockUniswapV2Factory;
		let usdt: MockERC20;
		let usdc: MockERC20;
		let simpleOracle: SimpleOracle;
		let coreOracle: CoreOracle;

		beforeEach(async () => {
			const uniFixture = await setupUniswap();
			const basicFixture = await setupBasic();
			bank = basicFixture.homoraBank;
			werc20 = basicFixture.werc20;
			uniV2Router02 = uniFixture.mockUniV2Router02;
			uniV2Factory = uniFixture.mockUniV2Factory;
			usdt = basicFixture.usdt;
			usdc = basicFixture.usdc;
			simpleOracle = basicFixture.simpleOracle;
			coreOracle = basicFixture.coreOracle;
		})
		it('temporary state', async () => {
			const NOT_ENTERED = 1;
			const ENTERED = 2;
			const NO_ID = ethers.constants.MaxUint256;

			expect(await bank._GENERAL_LOCK()).to.be.equal(NOT_ENTERED);
			expect(await bank._IN_EXEC_LOCK()).to.be.equal(NOT_ENTERED);
			expect(await bank.POSITION_ID()).to.be.equal(NO_ID);
			expect(await bank.SPELL()).to.be.equal(ethers.constants.AddressZero);

			const spell = await setup_uniswap(
				admin,
				alice,
				bank,
				werc20,
				uniV2Router02,
				uniV2Factory,
				usdc,
				usdt,
				simpleOracle,
				coreOracle,
				coreOracle
			)

			await execute_uniswap_werc20(
				alice,
				bank,
				usdc.address,
				usdt.address,
				spell,
				0,
				''
			)

			expect(await bank._GENERAL_LOCK()).to.be.equal(NOT_ENTERED);
			expect(await bank._IN_EXEC_LOCK()).to.be.equal(NOT_ENTERED);
			expect(await bank.POSITION_ID()).to.be.equal(NO_ID);
			expect(await bank.SPELL()).to.be.equal(ethers.constants.AddressZero);
		})
	})
})