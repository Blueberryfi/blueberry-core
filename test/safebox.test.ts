import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers, upgrades } from "hardhat";
import chai, { expect } from "chai";
import { ERC20, ICErc20, IUniswapV2Router02, IWETH, ProtocolConfig, SafeBox } from "../typechain-types";
import { ADDRESS, CONTRACT_NAMES } from "../constant";
import { solidity } from 'ethereum-waffle'
import { BigNumber, utils } from "ethers";
import { roughlyNear } from "./assertions/roughlyNear";
import { near } from "./assertions/near";

chai.use(solidity);
chai.use(roughlyNear);
chai.use(near);

const CUSDC = ADDRESS.bUSDC;
const USDC = ADDRESS.USDC;
const WETH = ADDRESS.WETH;

describe("SafeBox", () => {
	let admin: SignerWithAddress;
	let alice: SignerWithAddress;
	let bank: SignerWithAddress;
	let treasury: SignerWithAddress;

	let usdc: ERC20;
	let weth: IWETH;
	let cUSDC: ICErc20;
	let safeBox: SafeBox;
	let config: ProtocolConfig;

	before(async () => {
		[admin, alice, bank, treasury] = await ethers.getSigners();
		usdc = <ERC20>await ethers.getContractAt("ERC20", USDC, admin);
		weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);
		cUSDC = <ICErc20>await ethers.getContractAt("ICErc20", CUSDC);

		const ProtocolConfig = await ethers.getContractFactory("ProtocolConfig");
		config = <ProtocolConfig>await upgrades.deployProxy(ProtocolConfig, [treasury.address]);
	})

	beforeEach(async () => {
		const SafeBox = await ethers.getContractFactory(CONTRACT_NAMES.SafeBox);
		safeBox = <SafeBox>await upgrades.deployProxy(SafeBox, [
			config.address,
			CUSDC,
			"Interest Bearing USDC",
			"ibUSDC",
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
			await expect(upgrades.deployProxy(SafeBox, [
				config.address,
				ethers.constants.AddressZero,
				"Interest Bearing USDC",
				"ibUSDC",
			])).to.be.revertedWith('ZERO_ADDRESS');
			await expect(upgrades.deployProxy(SafeBox, [
				ethers.constants.AddressZero,
				CUSDC,
				"Interest Bearing USDC",
				"ibUSDC",
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
	describe("Deposit", () => {
		const depositAmount = utils.parseUnits("100", 6);
		beforeEach(async () => { })
		it("should revert if deposit amount is zero", async () => {
			await expect(safeBox.deposit(0)).to.be.revertedWith("ZERO_AMOUNT");
		})
		it("should be able to deposit underlying token on SafeBox", async () => {
			await usdc.approve(safeBox.address, depositAmount);
			await expect(safeBox.deposit(depositAmount)).to.be.emit(safeBox, "Deposited");
		})
		it("safebox should hold the cTokens", async () => {
			await usdc.approve(safeBox.address, depositAmount);
			await safeBox.deposit(depositAmount);

			const exchangeRate = await cUSDC.exchangeRateStored()
			expect(await cUSDC.balanceOf(safeBox.address)).to.be.equal(
				depositAmount.mul(BigNumber.from(10).pow(18)).div(exchangeRate)
			);
		})
		it("safebox should mint same amount of share tokens as cTokens received", async () => {
			await usdc.approve(safeBox.address, depositAmount);
			await safeBox.deposit(depositAmount);

			const cBalance = await cUSDC.balanceOf(safeBox.address);
			const shareBalance = await safeBox.balanceOf(admin.address);
			expect(cBalance).to.be.equal(shareBalance);
		})
	})

	describe("Withdraw", () => {
		const depositAmount = utils.parseUnits("100", 6);

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
			const feeRate = await config.withdrawSafeBoxFee();
			const fee = depositAmount.mul(feeRate).div(10000);
			const treasuryBalance = await usdc.balanceOf(treasury.address);
			expect(treasuryBalance).to.be.equal(fee);

			expect(afterUSDCBalance.sub(beforeUSDCBalance)).to.be.roughlyNear(depositAmount.sub(fee));
		})
	})

	describe("Utils", () => {
		it("should have same decimal as cToken", async () => {
			expect(await safeBox.decimals()).to.be.equal(6);
		})
	})
})