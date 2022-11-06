import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers, upgrades } from "hardhat";
import chai, { expect } from "chai";
import { ERC20, ICErc20, IUniswapV2Router02, IWETH, SafeBox } from "../typechain-types";
import { ADDRESS, CONTRACT_NAMES } from "../constant";
import ERC20ABI from '../abi/ERC20.json'
import ICrc20ABI from '../abi/ICErc20.json'
import { solidity } from 'ethereum-waffle'
import { BigNumber, utils } from "ethers";
import { roughlyNear } from "./assertions/roughlyNear";
import { near } from "./assertions/near";
import { evm_mine_blocks } from "./helpers";

chai.use(solidity);
chai.use(roughlyNear);
chai.use(near);

const CUSDC = ADDRESS.cyUSDC;			// IronBank cyUSDC
const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const ICHI = ADDRESS.ICHI;

describe("SafeBox", () => {
	let admin: SignerWithAddress;
	let alice: SignerWithAddress;
	let bank: SignerWithAddress;

	let usdc: ERC20;
	let weth: IWETH;
	let cUSDC: ICErc20;
	let safeBox: SafeBox;

	before(async () => {
		[admin, alice, bank] = await ethers.getSigners();
		usdc = <ERC20>await ethers.getContractAt(ERC20ABI, USDC, admin);
		weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);
		cUSDC = <ICErc20>await ethers.getContractAt(ICrc20ABI, CUSDC);
	})

	beforeEach(async () => {
		const SafeBox = await ethers.getContractFactory(CONTRACT_NAMES.SafeBox);
		safeBox = <SafeBox>await upgrades.deployProxy(SafeBox, [
			CUSDC,
			"Interest Bearing USDC",
			"ibUSDC"
		]);
		await safeBox.deployed();

		// deposit 50 eth -> 50 WETH
		await weth.deposit({ value: utils.parseUnits('50') });
		await weth.approve(ADDRESS.UNI_V2_ROUTER, ethers.constants.MaxUint256);

		// swap 50 weth -> usdc
		const uniV2Router = <IUniswapV2Router02>await ethers.getContractAt(
			CONTRACT_NAMES.IUniswapV2Router02,
			ADDRESS.UNI_V2_ROUTER
		);
		await uniV2Router.swapExactTokensForTokens(
			utils.parseUnits('50'),
			0,
			[WETH, USDC],
			admin.address,
			ethers.constants.MaxUint256
		)
	})

	describe("Constructor", () => {
		it("should revert when cToken address is invalid", async () => {
			const SafeBox = await ethers.getContractFactory(CONTRACT_NAMES.SafeBox);
			// const safeBox = <SafeBox>
			await expect(upgrades.deployProxy(SafeBox, [
				ethers.constants.AddressZero,
				"Interest Bearing USDC",
				"ibUSDC"
			])).to.be.revertedWith('ZERO_ADDRESS');
		})
		it("should set cToken along with uToken in constructor", async () => {
			expect(await safeBox.uToken()).to.be.equal(USDC);
			expect(await safeBox.cToken()).to.be.equal(CUSDC);
		})
		it("should grant max allowance of uToken to cToken address", async () => {
			expect(await usdc.allowance(safeBox.address, CUSDC)).to.be.equal(ethers.constants.MaxUint256);
		})
	})
	describe("Owner", () => {
		it("should be able to set bank", async () => {
			await expect(
				safeBox.connect(alice).setBank(bank.address)
			).to.be.revertedWith('Ownable: caller is not the owner');

			await safeBox.setBank(bank.address);
			expect(await safeBox.bank()).to.be.equal(bank.address);
		})
	})

	describe("Deposit", () => {
		beforeEach(async () => { })
		it("should revert if deposit amount is zero", async () => {
			await expect(safeBox.deposit(0)).to.be.revertedWith("ZERO_AMOUNT");
		})
		it("should be able to deposit underlying token on SafeBox", async () => {
			const depositAmount = utils.parseUnits("100", 8);
			await usdc.approve(safeBox.address, depositAmount);
			await expect(safeBox.deposit(depositAmount)).to.be.emit(safeBox, "Deposited");
		})
		it("safebox should hold the cTokens", async () => {
			const depositAmount = utils.parseUnits("100", 8);
			await usdc.approve(safeBox.address, depositAmount);
			await safeBox.deposit(depositAmount);

			const exchangeRate = await cUSDC.exchangeRateStored()
			expect(await cUSDC.balanceOf(safeBox.address)).to.be.equal(
				depositAmount.mul(BigNumber.from(10).pow(18)).div(exchangeRate)
			);
		})
		it("safebox should mint same amount of share tokens as cTokens received", async () => {
			const depositAmount = utils.parseUnits("100", 8);
			await usdc.approve(safeBox.address, depositAmount);
			await safeBox.deposit(depositAmount);

			const cBalance = await cUSDC.balanceOf(safeBox.address);
			const shareBalance = await safeBox.balanceOf(admin.address);
			expect(cBalance).to.be.equal(shareBalance);
		})
	})

	describe("Withdraw", () => {
		const depositAmount = utils.parseUnits("100", 8);

		beforeEach(async () => {
			await usdc.approve(safeBox.address, depositAmount);
			await safeBox.deposit(depositAmount);
		})

		it("should revert if withdraw amount is zero", async () => {
			await expect(safeBox.withdraw(0)).to.be.revertedWith("ZERO_AMOUNT");
		})

		it("should be able to withdraw underlying tokens from SafeBox with rewards", async () => {
			const beforeUSDCBalance = await usdc.balanceOf(admin.address);
			const shareBalance = await safeBox.balanceOf(admin.address);

			await expect(
				safeBox.withdraw(shareBalance)
			).to.be.emit(safeBox, "Withdrawn");

			expect(await safeBox.balanceOf(admin.address)).to.be.equal(0);
			expect(await cUSDC.balanceOf(safeBox.address)).to.be.equal(0);

			const afterUSDCBalance = await usdc.balanceOf(admin.address);
			expect(afterUSDCBalance.sub(beforeUSDCBalance)).to.be.roughlyNear(depositAmount);
			expect(afterUSDCBalance.sub(beforeUSDCBalance)).to.be.gt(depositAmount);
		})
	})

	describe("Borrow", () => {
		const depositAmount = utils.parseUnits("1000", 8);
		const borrowAmount = utils.parseUnits("100", 8);

		beforeEach(async () => {
			await safeBox.setBank(bank.address);
			await usdc.approve(safeBox.address, depositAmount);
			await safeBox.deposit(depositAmount);
		})
		it("should revert borrow function from non-bank address", async () => {
			await expect(safeBox.borrow(borrowAmount)).to.be.revertedWith("NOT_BANK");
		})
		it("should revert when borrowing zero amount", async () => {
			await expect(safeBox.connect(bank).borrow(0)).to.be.revertedWith("ZERO_AMOUNT");
		})
		it("should be able to borrow underlying tokens from compound", async () => {
			const beforeDebt = await cUSDC.borrowBalanceStored(safeBox.address);
			await expect(
				safeBox.connect(bank).borrow(borrowAmount)
			).to.be.emit(safeBox, "Borrowed").withArgs(borrowAmount);

			// should transfer underlying tokens back to the bank
			expect(await usdc.balanceOf(bank.address)).to.be.equal(borrowAmount);

			// safebox should have no dust of underlying tokens left on it
			expect(await usdc.balanceOf(safeBox.address)).to.be.equal(0);

			// debt should be increased
			const newDebt = await cUSDC.borrowBalanceStored(safeBox.address);
			expect(newDebt.sub(beforeDebt)).to.be.equal(borrowAmount);
		})
	})

	describe("Repay", () => {
		const depositAmount = utils.parseUnits("1000", 8);
		const borrowAmount = utils.parseUnits("100", 8);

		beforeEach(async () => {
			// lending initial liquidity
			await usdc.approve(safeBox.address, depositAmount);
			await safeBox.deposit(depositAmount);

			await safeBox.setBank(bank.address);

			// borrow
			await safeBox.connect(bank).borrow(borrowAmount);
			await usdc.connect(bank).approve(safeBox.address, ethers.constants.MaxUint256);
		})
		it("should revert repay from non-bank address", async () => {
			const debt = await cUSDC.borrowBalanceStored(safeBox.address);
			await expect(safeBox.repay(debt)).to.be.revertedWith('NOT_BANK');
		})
		it("should revert when repaying zero amount", async () => {
			await expect(safeBox.connect(bank).repay(0)).to.be.revertedWith('ZERO_AMOUNT');
		})
		it("should be able to repay debts to compound", async () => {
			await cUSDC.borrowBalanceCurrent(safeBox.address);
			const debt1 = await cUSDC.borrowBalanceStored(safeBox.address);
			await cUSDC.borrowBalanceCurrent(safeBox.address);
			const debt2 = await cUSDC.borrowBalanceStored(safeBox.address);
			const expectedDebt = debt2.sub(debt1).mul(2).add(debt2).sub(1);

			await usdc.connect(bank).transfer(safeBox.address, expectedDebt);
			await expect(safeBox.connect(bank).repay(expectedDebt)).to.be.emit(safeBox, "Repaid");

			await cUSDC.borrowBalanceCurrent(safeBox.address);
			const curDebt = await cUSDC.borrowBalanceStored(safeBox.address);
			// remaining debt should be dust
			expect(BigNumber.from(100000).sub(curDebt)).to.be.roughlyNear(BigNumber.from(100000));
			expect(await usdc.balanceOf(safeBox.address)).to.be.equal(0);
		})
	})

	describe("Utils", () => {
		it("should be able to set valid address for bank", async () => {
			await expect(safeBox.setBank(ethers.constants.AddressZero)).to.be.revertedWith("ZERO_ADDRESS");

			await safeBox.setBank(bank.address);
			expect(await safeBox.bank()).to.be.equal(bank.address);
		})
		it("should have same decimal as cToken", async () => {
			expect(await safeBox.decimals()).to.be.equal(8);
		})
	})
})