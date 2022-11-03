import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";
import chai, { expect } from "chai";
import { ERC20, ICErc20, IUniswapV2Router02, IWETH, SafeBox } from "../typechain-types";
import { ADDRESS, CONTRACT_NAMES } from "../constant";
import ERC20ABI from '../abi/ERC20.json'
import ICrc20ABI from '../abi/ICErc20.json'
import { solidity } from 'ethereum-waffle'
import { BigNumber, utils } from "ethers";
import { roughlyNear } from "./assertions/roughlyNear";
import { near } from "./assertions/near";

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

	let usdc: ERC20;
	let weth: IWETH;
	let cUSDC: ICErc20;
	let safeBox: SafeBox;

	before(async () => {
		[admin, alice] = await ethers.getSigners();
		usdc = <ERC20>await ethers.getContractAt(ERC20ABI, USDC, admin);
		weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);
		cUSDC = <ICErc20>await ethers.getContractAt(ICrc20ABI, CUSDC);
	})

	beforeEach(async () => {
		const SafeBox = await ethers.getContractFactory(CONTRACT_NAMES.SafeBox);
		safeBox = <SafeBox>await SafeBox.deploy(
			CUSDC,
			"Interest Bearing USDC",
			"ibUSDC"
		)
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
			await expect(SafeBox.deploy(
				ethers.constants.AddressZero,
				"Interest Bearing USDC",
				"ibUSDC"
			)).to.be.revertedWith('zero address');
		})
		it("should set cToken along with uToken in constructor", async () => {
			expect(await safeBox.uToken()).to.be.equal(USDC);
			expect(await safeBox.cToken()).to.be.equal(CUSDC);
		})
		it("should grant max allowance of uToken to cToken address", async () => {
			expect(await usdc.allowance(safeBox.address, CUSDC)).to.be.equal(ethers.constants.MaxUint256);
		})
	})

	describe("Deposit", () => {
		beforeEach(async () => { })
		it("should revert if deposit amount is zero", async () => {
			await expect(safeBox.deposit(0)).to.be.revertedWith("zero amount");
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
			await expect(safeBox.withdraw(0)).to.be.revertedWith("zero amount");
		})

		it("should be able to withdraw underlying tokens from SafeBox", async () => {
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

	// TODO: set bank address and cover borrow and repay functions
	describe("Borrow", () => {
		const borrowAmount = utils.parseUnits("100", 8);
		it("should revert borrow function from non-bank address", async () => {
			await expect(safeBox.borrow(borrowAmount)).to.be.revertedWith("!bank");
		})
	})

	describe("Utils", () => {
		it("should be able to set valid address for bank", async () => {
			await expect(safeBox.setBank(ethers.constants.AddressZero)).to.be.revertedWith("zero address");
		})
		it("should have same decimal as cToken", async () => {
			expect(await safeBox.decimals()).to.be.equal(8);
		})
		it("admin should be able to claim fees from SafeBox", async () => {

		})

	})
})