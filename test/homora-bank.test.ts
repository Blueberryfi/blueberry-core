import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai, { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { CONTRACT_NAMES } from "../constants"
import { CoreOracle, ERC20, HomoraBank, MockCErc20, MockERC20, MockUniswapV2Factory, MockUniswapV2Router02, MockWETH, SimpleOracle, WERC20 } from '../typechain';
import { execute_uniswap_werc20, setup_uniswap } from './helpers/helper-uniswap';
import { setupBasic } from './helpers/setup-basic';
import { setupUniswap } from './helpers/setup-uniswap';
import { solidity } from 'ethereum-waffle'
import { near } from './assertions/near'
import { roughlyNear } from './assertions/roughlyNear'

chai.use(solidity)
chai.use(near)
chai.use(roughlyNear)

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
		let dai: MockERC20;
		let weth: MockWETH;
		let simpleOracle: SimpleOracle;
		let coreOracle: CoreOracle;
		let token: MockERC20;
		let cToken: MockCErc20;

		beforeEach(async () => {
			const uniFixture = await setupUniswap();
			const basicFixture = await setupBasic();
			bank = basicFixture.homoraBank;
			werc20 = basicFixture.werc20;
			uniV2Router02 = uniFixture.mockUniV2Router02;
			uniV2Factory = uniFixture.mockUniV2Factory;
			usdt = basicFixture.usdt;
			usdc = basicFixture.usdc;
			dai = basicFixture.dai;
			weth = basicFixture.mockWETH;
			simpleOracle = basicFixture.simpleOracle;
			coreOracle = basicFixture.coreOracle;

			const MockERC20 = await ethers.getContractFactory(CONTRACT_NAMES.MockERC20);
			const MockCERC20 = await ethers.getContractFactory(CONTRACT_NAMES.MockCErc20);
			token = <MockERC20>await MockERC20.deploy("Test", "TEST", 18);
			await token.deployed();
			cToken = <MockCErc20>await MockCERC20.deploy(token.address);
			await cToken.deployed();
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

		it("test oracle", async () => {
			expect(await bank.oracle()).to.be.equal(coreOracle.address);
		})

		it("test fee", async () => {
			expect(await bank.feeBps()).to.be.equal(2000);
		})

		it("next position id", async () => {
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
			// initially 1
			expect(await bank.nextPositionId()).to.be.equal(1);
			await execute_uniswap_werc20(alice, bank, usdc.address, usdt.address, spell, 0, '')
			expect(await bank.nextPositionId()).to.be.equal(2);
			// don't increase due to changing
			await execute_uniswap_werc20(alice, bank, usdc.address, usdt.address, spell, 1, '')
			expect(await bank.nextPositionId()).to.be.equal(2);
			await execute_uniswap_werc20(alice, bank, usdc.address, usdt.address, spell, 0, '')
			expect(await bank.nextPositionId()).to.be.equal(3);
		})
		it("test all banks", async () => {
			expect(await bank.allBanks(0)).to.be.equal(weth.address);
			expect(await bank.allBanks(1)).to.be.equal(dai.address);
			expect(await bank.allBanks(2)).to.be.equal(usdt.address);
			expect(await bank.allBanks(3)).to.be.equal(usdc.address);

			await expect(bank.allBanks(4)).to.be.reverted;

			await bank.addBank(token.address, cToken.address);
			expect(await bank.allBanks(4)).to.be.equal(token.address);

			await expect(
				bank.addBank(token.address, cToken.address)
			).to.be.revertedWith('cToken already exists');

			const MockCERC20 = await ethers.getContractFactory(CONTRACT_NAMES.MockCErc20);
			const cToken1 = await MockCERC20.deploy(token.address);
			await cToken1.deployed();
			await expect(
				bank.addBank(token.address, cToken1.address)
			).to.be.revertedWith('bank already exists');
		})


		it("test banks", async () => {
			(await Promise.all(([weth, dai, usdt, usdc]).map(
				coin => bank.banks(coin.address)
			))).forEach((res, index) => {
				expect(res.isListed).to.be.true;
				expect(res.index).to.be.equal(index);
				expect(res.reserve).to.be.equal(0);
				// expect(res.pendingReserve).to.be.equal(0);
				expect(res.totalDebt).to.be.equal(0);
				expect(res.totalShare).to.be.equal(0);
			})

			// token is not listed yet
			const MockERC20 = await ethers.getContractFactory(CONTRACT_NAMES.MockERC20);
			const MockCERC20 = await ethers.getContractFactory(CONTRACT_NAMES.MockCErc20);
			const token = await MockERC20.deploy("Test", "TEST", 18);
			await token.deployed();
			const cToken = await MockCERC20.deploy(token.address);
			await cToken.deployed();

			const res = await bank.banks(token.address);
			expect(res.isListed).to.be.false;
			expect(res.index).to.be.equal(0);
			expect(res.reserve).to.be.equal(0);
			// expect(res.pendingReserve).to.be.equal(0);
			expect(res.totalDebt).to.be.equal(0);
			expect(res.totalShare).to.be.equal(0);

			// add bank
			await bank.addBank(token.address, cToken.address);
			const res1 = await bank.banks(token.address);
			expect(res1.isListed).to.be.true;
			expect(res1.index).to.be.equal(4);
			expect(res1.reserve).to.be.equal(0);
			// expect(res1.pendingReserve).to.be.equal(0);
			expect(res1.totalDebt).to.be.equal(0);
			expect(res1.totalShare).to.be.equal(0);
		})

		it("test cToken in bank", async () => {
			const cTokensInBank = await Promise.all((await Promise.all(([weth, dai, usdt, usdc]).map(
				coin => bank.banks(coin.address)
			))).map(res => bank.cTokenInBank(res.cToken)))
			cTokensInBank.forEach(cTokenInBank => {
				expect(cTokenInBank).to.be.true;
			})

			expect(await bank.cTokenInBank(cToken.address)).to.be.false;

			await bank.addBank(token.address, cToken.address);
			expect(await bank.cTokenInBank(cToken.address)).to.be.true;
		})

		it("test positions", async () => {
			let { owner, collToken, collId, collateralSize, debtMap } = await bank.positions(1);
			expect(owner).to.be.eq(ethers.constants.AddressZero);
			expect(collToken).to.be.eq(ethers.constants.AddressZero);
			expect(collId).to.be.eq(0);
			expect(collateralSize).to.be.eq(0);
			expect(debtMap).to.be.eq(0);

			// create position 1
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
			await execute_uniswap_werc20(alice, bank, usdc.address, usdt.address, spell, 0, '')

			let position1 = await bank.positions(1);
			const lp = await spell.pairs(usdt.address, usdc.address);
			expect(position1.owner).to.be.equal(alice.address);
			expect(collToken).to.be.equal(werc20.address);
			expect(collId).to.be.equal(BigNumber.from(lp))
			expect(collateralSize).to.be.gt(0);
			expect(debtMap).to.be.equal(1 << 2 + 1 << 3);
		})

		it("reinitialize", async () => {
			await expect(bank.initialize(coreOracle.address, 2000)).to.be.reverted;
		})

		it("test accure", async () => {
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
			await execute_uniswap_werc20(alice, bank, usdc.address, usdt.address, spell, 0, '')

			const prevBank = await bank.banks(usdt.address);
			console.log('totalDebt:', prevBank.totalDebt.toString())
			console.log('totalShare:', prevBank.totalShare.toString())

			// chain.sleep(100_000)

			// not accure yet
			const curBank = await bank.banks(usdt.address);
			console.log('totalDebt:', curBank.totalDebt.toString())
			console.log('totalShare:', curBank.totalShare.toString())

			expect(prevBank.totalDebt).to.be.equal(curBank.totalDebt);
			expect(prevBank.totalShare).to.be.equal(curBank.totalShare);

			await bank.accrue(usdt.address);

			const curBank1 = await bank.banks(usdt.address);
			console.log('totalDebt:', curBank1.totalDebt.toString())
			console.log('totalShare:', curBank1.totalShare.toString())

			expect(prevBank.totalShare).to.be.equal(curBank1.totalShare);

			const usdtInterest = curBank1.totalDebt.sub(prevBank.totalDebt);
			const usdtFee = usdtInterest.mul(await bank.feeBps()).div(10_000);

			expect(curBank1.reserve.sub(prevBank.reserve)).to.be.equal(usdtFee);
		})

		it("test accure all", async () => {
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
			await execute_uniswap_werc20(alice, bank, usdc.address, usdt.address, spell, 0, '')

			const prevUSDTBank = await bank.banks(usdt.address);
			console.log('usdt totalDebt:', prevUSDTBank.totalDebt.toString())
			console.log('usdt totalShare:', prevUSDTBank.totalShare.toString())

			const prevUSDCBank = await bank.banks(usdc.address);
			console.log('usdc totalDebt:', prevUSDCBank.totalDebt.toString())
			console.log('usdc totalShare:', prevUSDCBank.totalShare.toString())

			// chain.sleep(100_000)

			let curUSDTBank = await bank.banks(usdt.address);
			let curUSDCBank = await bank.banks(usdc.address);

			expect(prevUSDTBank.totalDebt).to.be.equal(curUSDTBank.totalDebt)
			expect(prevUSDTBank.totalShare).to.be.equal(curUSDTBank.totalShare)

			expect(prevUSDCBank.totalDebt).to.be.equal(curUSDCBank.totalDebt)
			expect(prevUSDCBank.totalShare).to.be.equal(curUSDCBank.totalShare)

			// accure usdt, usdc
			await bank.accrueAll([usdt.address, usdc.address]);

			curUSDTBank = await bank.banks(usdt.address);
			console.log('usdt totalDebt:', curUSDTBank.totalDebt.toString())
			console.log('usdt totalShare:', curUSDTBank.totalShare.toString())

			expect(prevUSDTBank.totalShare).to.be.equal(curUSDTBank.totalShare);

			const usdtInterest = curUSDTBank.totalDebt.sub(prevUSDTBank.totalDebt);
			const usdtFee = usdtInterest.mul(await bank.feeBps()).div(10_000);

			expect(curUSDTBank.reserve.sub(prevUSDTBank.reserve)).to.be.equal(usdtFee);

			expect(usdtInterest).to.be.roughlyNear(
				BigNumber.from(200_000_000).mul(10).div(100).mul(100_000).div(365 * 86400)
			);

			curUSDCBank = await bank.banks(usdc.address);
			console.log('usdc totalDebt:', curUSDCBank.totalDebt);
			console.log('usdc totalShare:', curUSDCBank.totalShare);

			expect(prevUSDCBank.totalShare).to.be.equal(curUSDCBank.totalShare);

			const usdcInterest = curUSDCBank.totalDebt.sub(prevUSDCBank.totalDebt);
			const usdcFee = usdcInterest.mul(await bank.feeBps()).div(10_000);

			expect(curUSDCBank.reserve.sub(prevUSDCBank.reserve)).to.be.equal(usdcFee);
			expect(usdcInterest).to.be.roughlyNear(
				BigNumber.from(1_000_000_000).mul(10).div(100).mul(100_000).div(365 * 86400)
			);
		})
	})
})