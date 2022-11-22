import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers, upgrades } from "hardhat";
import chai, { expect } from "chai";
import { ICErc20, MockERC20, SafeBox } from "../typechain-types";
import { ADDRESS_GOERLI, CONTRACT_NAMES } from "../constant";
import ICrc20ABI from '../abi/ICErc20.json'
import { solidity } from 'ethereum-waffle'
import { BigNumber, utils } from "ethers";
import { roughlyNear } from "./assertions/roughlyNear";
import { near } from "./assertions/near";

chai.use(solidity);
chai.use(roughlyNear);
chai.use(near);

const CUSDC = ADDRESS_GOERLI.bUSDC;
const USDC = ADDRESS_GOERLI.MockUSDC;

describe("SafeBox", () => {
	let admin: SignerWithAddress;
	let alice: SignerWithAddress;
	let bank: SignerWithAddress;

	let usdc: MockERC20;
	let cUSDC: ICErc20;
	let safeBox: SafeBox;

	before(async () => {
		[admin, alice, bank] = await ethers.getSigners();
		usdc = <MockERC20>await ethers.getContractAt("MockERC20", USDC, admin);
		cUSDC = <ICErc20>await ethers.getContractAt("ICErc20", CUSDC);
	})

	beforeEach(async () => {
		const SafeBox = await ethers.getContractFactory(CONTRACT_NAMES.SafeBox);
		safeBox = <SafeBox>await upgrades.deployProxy(SafeBox, [
			CUSDC,
			"Interest Bearing USDC",
			"ibUSDC"
		]);
		await safeBox.deployed();

		await usdc.mint(admin.address, utils.parseUnits("1000000", 6));
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
			expect(afterUSDCBalance.sub(beforeUSDCBalance)).to.be.roughlyNear(depositAmount);
			expect(afterUSDCBalance.sub(beforeUSDCBalance)).to.be.gte(depositAmount);
		})
	})

	describe("Utils", () => {
		it("should be able to set valid address for bank", async () => {
			await expect(safeBox.setBank(ethers.constants.AddressZero)).to.be.revertedWith("ZERO_ADDRESS");

			await safeBox.setBank(bank.address);
			expect(await safeBox.bank()).to.be.equal(bank.address);
		})
		it("should have same decimal as cToken", async () => {
			expect(await safeBox.decimals()).to.be.equal(6);
		})
	})
})