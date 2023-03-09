import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai, { expect } from 'chai';
import { BigNumber, utils } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import {
	BlueBerryBank,
	IchiSpell,
	IWETH,
	MockOracle,
	WERC20,
	WIchiFarm,
	MockIchiVault,
	MockIchiFarm,
	ERC20,
	MockIchiV2,
} from '../../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import SpellABI from '../../abi/IchiSpell.json';

import { solidity } from 'ethereum-waffle'
import { near } from '../assertions/near'
import { roughlyNear } from '../assertions/roughlyNear'
import { evm_mine_blocks } from '../helpers';
import { Protocol, setupProtocol } from '../setup-test';

chai.use(solidity)
chai.use(near)
chai.use(roughlyNear)

const CUSDC = ADDRESS.bUSDC;
const CICHI = ADDRESS.bICHI;
const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const ICHI = ADDRESS.ICHI;
const ICHIV1 = ADDRESS.ICHI_FARM;
const ICHI_VAULT_PID = 0; // ICHI/USDC Vault PoolId
const ETH_PRICE = 1600;

describe('ICHI Angel Vaults Spell', () => {
	let admin: SignerWithAddress;
	let alice: SignerWithAddress;
	let treasury: SignerWithAddress;

	let usdc: ERC20;
	let ichi: MockIchiV2;
	let ichiV1: ERC20;
	let weth: IWETH;
	let werc20: WERC20;
	let mockOracle: MockOracle;
	let spell: IchiSpell;
	let wichi: WIchiFarm;
	let bank: BlueBerryBank;
	let ichiFarm: MockIchiFarm;
	let ichiVault: MockIchiVault;
	let protocol: Protocol;

	before(async () => {
		[admin, alice, treasury] = await ethers.getSigners();
		usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
		ichi = <MockIchiV2>await ethers.getContractAt("MockIchiV2", ICHI);
		ichiV1 = <ERC20>await ethers.getContractAt("ERC20", ICHIV1);
		weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);

		protocol = await setupProtocol();
		bank = protocol.bank;
		spell = protocol.spell;
		ichiFarm = protocol.ichiFarm;
		ichiVault = protocol.ichi_USDC_ICHI_Vault;
		wichi = protocol.wichi;
		werc20 = protocol.werc20;
		mockOracle = protocol.mockOracle;
	})

	beforeEach(async () => {
	})

	describe("ICHI Vault Position", () => {
		const depositAmount = utils.parseUnits('100', 18); // worth of $400
		const borrowAmount = utils.parseUnits('300', 6);
		const iface = new ethers.utils.Interface(SpellABI);

		it("should revert when exceeds max LTV", async () => {
			await ichi.approve(bank.address, ethers.constants.MaxUint256);
			await expect(
				bank.execute(
					0,
					spell.address,
					iface.encodeFunctionData("openPosition", [
						0, ICHI, USDC, depositAmount, borrowAmount.mul(5)
					])
				)
			).to.be.revertedWith("EXCEED_MAX_LTV")
		})
		it("should revert when exceeds max pos size", async () => {
			await ichi.approve(bank.address, ethers.constants.MaxUint256);
			await expect(
				bank.execute(
					0,
					spell.address,
					iface.encodeFunctionData("openPosition", [
						0, ICHI, USDC, depositAmount.mul(4), borrowAmount.mul(7)
					])
				)
			).to.be.revertedWith("EXCEED_MAX_POS_SIZE")
		})
		it("should revert when opening a position for non-existing strategy", async () => {
			await ichi.approve(bank.address, ethers.constants.MaxUint256);
			await expect(
				bank.execute(
					0,
					spell.address,
					iface.encodeFunctionData("openPosition", [
						1, ICHI, USDC, depositAmount, borrowAmount
					])
				)
			).to.be.revertedWith("STRATEGY_NOT_EXIST")
		})
		it("should revert when opening a position for non-existing collateral", async () => {
			await ichi.approve(bank.address, ethers.constants.MaxUint256);
			await expect(
				bank.execute(
					0,
					spell.address,
					iface.encodeFunctionData("openPosition", [
						0, WETH, USDC, depositAmount, borrowAmount
					])
				)
			).to.be.revertedWith("COLLATERAL_NOT_EXIST")
		})
		it("should be able to open a position for ICHI angel vault", async () => {
			const beforeTreasuryBalance = await ichi.balanceOf(treasury.address);
			const beforeICHIBalance = await ichi.balanceOf(CICHI);

			// Isolated collateral: ICHI
			// Borrow: USDC
			await bank.execute(
				0,
				spell.address,
				iface.encodeFunctionData("openPosition", [
					0, ICHI, USDC, depositAmount, borrowAmount
				])
			)

			const fee = depositAmount.mul(50).div(10000);
			const afterICHIBalance = await ichi.balanceOf(CICHI);
			expect(afterICHIBalance.sub(beforeICHIBalance)).to.be.near(depositAmount.sub(fee))

			expect(await bank.nextPositionId()).to.be.equal(BigNumber.from(2));
			const pos = await bank.positions(1);
			expect(pos.owner).to.be.equal(admin.address);
			expect(pos.collToken).to.be.equal(werc20.address);
			expect(pos.collId).to.be.equal(BigNumber.from(ichiVault.address));
			expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;
			expect(
				await werc20.balanceOfERC20(ichiVault.address, bank.address)
			).to.be.equal(pos.collateralSize);
			const bankInfo = await bank.banks(USDC);
			console.log('Bank Info', bankInfo, await bank.banks(ICHI));
			console.log('Position Info', pos);

			const afterTreasuryBalance = await ichi.balanceOf(treasury.address);
			expect(
				afterTreasuryBalance.sub(beforeTreasuryBalance)
			).to.be.equal(depositAmount.mul(50).div(10000))
		})
		it("should be able to return position risk ratio", async () => {
			let risk = await bank.getPositionRisk(1);
			console.log('Prev Position Risk', utils.formatUnits(risk, 2), '%');
			await mockOracle.setPrice(
				[USDC, ICHI],
				[
					BigNumber.from(10).pow(18), // $1
					BigNumber.from(10).pow(17).mul(40), // $4
				]
			);
			risk = await bank.getPositionRisk(1);
			console.log('Position Risk', utils.formatUnits(risk, 2), '%');
		})
		it("should revert when opening a position for non-existing strategy", async () => {
			await ichi.approve(bank.address, ethers.constants.MaxUint256);
			await expect(
				bank.execute(
					1,
					spell.address,
					iface.encodeFunctionData("closePosition", [
						1,
						ICHI,
						USDC, // ICHI vault lp token is collateral
						ethers.constants.MaxUint256,	// Amount of werc20
						ethers.constants.MaxUint256,  // Amount of repay
						0,
						ethers.constants.MaxUint256,
					])
				)
			).to.be.revertedWith("STRATEGY_NOT_EXIST")
		})
		it("should revert when opening a position for non-existing collateral", async () => {
			await ichi.approve(bank.address, ethers.constants.MaxUint256);
			await expect(
				bank.execute(
					1,
					spell.address,
					iface.encodeFunctionData("closePosition", [
						0,
						WETH,
						USDC, // ICHI vault lp token is collateral
						ethers.constants.MaxUint256,	// Amount of werc20
						ethers.constants.MaxUint256,  // Amount of repay
						0,
						ethers.constants.MaxUint256,
					])
				)
			).to.be.revertedWith("COLLATERAL_NOT_EXIST")
		})
		it("should be able to withdraw USDC", async () => {
			await ichiVault.rebalance(-260400, -260200, -260800, -260600, 0);
			await usdc.transfer(spell.address, utils.parseUnits('10', 6)); // manually set rewards

			const beforeTreasuryBalance = await ichi.balanceOf(treasury.address);
			const beforeUSDCBalance = await usdc.balanceOf(admin.address);
			const beforeIchiBalance = await ichi.balanceOf(admin.address);

			const iface = new ethers.utils.Interface(SpellABI);
			await bank.execute(
				1,
				spell.address,
				iface.encodeFunctionData("closePosition", [
					0,
					ICHI,
					USDC, // ICHI vault lp token is collateral
					ethers.constants.MaxUint256,	// Amount of werc20
					ethers.constants.MaxUint256,  // Amount of repay
					0,
					ethers.constants.MaxUint256,
				])
			)

			const afterUSDCBalance = await usdc.balanceOf(admin.address);
			const afterIchiBalance = await ichi.balanceOf(admin.address);
			console.log('USDC Balance Change:', afterUSDCBalance.sub(beforeUSDCBalance));
			console.log('ICHI Balance Change:', afterIchiBalance.sub(beforeIchiBalance));
			const depositFee = depositAmount.mul(50).div(10000);
			const withdrawFee = depositAmount.sub(depositFee).mul(50).div(10000);
			expect(afterIchiBalance.sub(beforeIchiBalance)).to.be.gte(depositAmount.sub(depositFee).sub(withdrawFee));

			const afterTreasuryBalance = await ichi.balanceOf(treasury.address);
			expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.equal(withdrawFee);
		})
	})

	describe("ICHI Vault Farming Position", () => {
		const depositAmount = utils.parseUnits('100', 18); // ICHI => $4.17 at current block
		const borrowAmount = utils.parseUnits('500', 6);	 // USDC
		const iface = new ethers.utils.Interface(SpellABI);

		beforeEach(async () => {
			await usdc.approve(bank.address, ethers.constants.MaxUint256);
			await ichi.approve(bank.address, ethers.constants.MaxUint256);
		})

		it("should revert when opening position exceeds max LTV", async () => {
			await expect(bank.execute(
				0,
				spell.address,
				iface.encodeFunctionData("openPositionFarm", [
					0,
					ICHI,
					USDC,
					depositAmount,
					borrowAmount.mul(3),
					ICHI_VAULT_PID // ICHI/USDC Vault Pool Id
				])
			)).to.be.revertedWith("EXCEED_MAX_LTV");
		})
		it("should revert when opening a position for non-existing strategy", async () => {
			await ichi.approve(bank.address, ethers.constants.MaxUint256);
			await expect(
				bank.execute(
					0,
					spell.address,
					iface.encodeFunctionData("openPositionFarm", [
						1, ICHI, USDC, depositAmount, borrowAmount, ICHI_VAULT_PID
					])
				)
			).to.be.revertedWith("STRATEGY_NOT_EXIST")
		})
		it("should revert when opening a position for non-existing collateral", async () => {
			await ichi.approve(bank.address, ethers.constants.MaxUint256);
			await expect(
				bank.execute(
					0,
					spell.address,
					iface.encodeFunctionData("openPositionFarm", [
						0, WETH, USDC, depositAmount, borrowAmount, ICHI_VAULT_PID
					])
				)
			).to.be.revertedWith("COLLATERAL_NOT_EXIST")
		})
		it("should revert when opening a position for incorrect farming pool id", async () => {
			await ichi.approve(bank.address, ethers.constants.MaxUint256);
			await expect(
				bank.execute(
					0,
					spell.address,
					iface.encodeFunctionData("openPositionFarm", [
						0, ICHI, USDC, depositAmount, borrowAmount, ICHI_VAULT_PID + 1
					])
				)
			).to.be.revertedWith("INCORRECT_LP")
		})
		it("should be able to farm USDC on ICHI angel vault", async () => {
			const positionId = await bank.nextPositionId();
			const beforeTreasuryBalance = await ichi.balanceOf(treasury.address);

			await usdc.approve(bank.address, ethers.constants.MaxUint256);
			await ichi.approve(bank.address, ethers.constants.MaxUint256);
			await bank.execute(
				0,
				spell.address,
				iface.encodeFunctionData("openPositionFarm", [
					0,
					ICHI,
					USDC,
					depositAmount,
					borrowAmount,
					ICHI_VAULT_PID // ICHI/USDC Vault Pool Id
				])
			)

			const bankInfo = await bank.getBankInfo(USDC);
			console.log(bankInfo);

			expect(await bank.nextPositionId()).to.be.equal(BigNumber.from(3));
			const pos = await bank.positions(positionId);
			expect(pos.owner).to.be.equal(admin.address);
			expect(pos.collToken).to.be.equal(wichi.address);
			expect(pos.debtToken).to.be.equal(USDC);
			const poolInfo = await ichiFarm.poolInfo(ICHI_VAULT_PID);
			const collId = await wichi.encodeId(ICHI_VAULT_PID, poolInfo.accIchiPerShare);
			expect(pos.collId).to.be.equal(collId);
			expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;
			expect(
				await wichi.balanceOf(bank.address, collId)
			).to.be.equal(pos.collateralSize);

			const afterTreasuryBalance = await ichi.balanceOf(treasury.address);
			expect(
				afterTreasuryBalance.sub(beforeTreasuryBalance)
			).to.be.equal(depositAmount.mul(50).div(10000))
		})
		it("should be able to get position risk ratio", async () => {
			let risk = await bank.getPositionRisk(2);
			console.log('Prev Position Risk', utils.formatUnits(risk, 2), '%');
			await mockOracle.setPrice(
				[USDC, ICHI],
				[
					BigNumber.from(10).pow(18), // $1
					BigNumber.from(10).pow(17).mul(40), // $4
				]
			);
			risk = await bank.getPositionRisk(2);
			console.log('Position Risk', utils.formatUnits(risk, 2), '%');
		})
		it("should be able to harvest on ICHI farming", async () => {
			evm_mine_blocks(1000);
			await ichiVault.rebalance(-260400, -260200, -260800, -260600, 0);
			await usdc.transfer(spell.address, utils.parseUnits('10', 6)); // manually set rewards

			const pendingIchi = await ichiFarm.pendingIchi(ICHI_VAULT_PID, wichi.address);
			console.log("Pending Rewards:", pendingIchi);
			await ichiV1.transfer(ichiFarm.address, pendingIchi.mul(100))

			const beforeTreasuryBalance = await ichi.balanceOf(treasury.address);
			const beforeUSDCBalance = await usdc.balanceOf(admin.address);
			const beforeIchiBalance = await ichi.balanceOf(admin.address);

			const iface = new ethers.utils.Interface(SpellABI);
			await bank.execute(
				2,
				spell.address,
				iface.encodeFunctionData("closePositionFarm", [
					0,
					ICHI,
					USDC, // ICHI vault lp token is collateral
					ethers.constants.MaxUint256,	// Amount of werc20
					ethers.constants.MaxUint256,  // Amount of repay
					0,
					ethers.constants.MaxUint256,
				])
			)
			const afterUSDCBalance = await usdc.balanceOf(admin.address);
			const afterIchiBalance = await ichi.balanceOf(admin.address);
			console.log('USDC Balance Change:', afterUSDCBalance.sub(beforeUSDCBalance));
			console.log('ICHI Balance Change:', afterIchiBalance.sub(beforeIchiBalance));
			const depositFee = depositAmount.mul(50).div(10000);
			const withdrawFee = depositAmount.sub(depositFee).mul(50).div(10000);
			expect(afterIchiBalance.sub(beforeIchiBalance)).to.be.gte(depositAmount.sub(depositFee).sub(withdrawFee));

			const afterTreasuryBalance = await ichi.balanceOf(treasury.address);
			// Plus rewards fee
			expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.gte(withdrawFee);
		})
	})

	describe("Increase/decrease", () => {
		const depositAmount = utils.parseUnits('100', 18); // ICHI => $4.17 at current block
		const borrowAmount = utils.parseUnits('500', 6);	 // USDC
		const iface = new ethers.utils.Interface(SpellABI);

		beforeEach(async () => {
			await usdc.approve(bank.address, ethers.constants.MaxUint256);
			await ichi.approve(bank.address, ethers.constants.MaxUint256);

			await bank.execute(
				0,
				spell.address,
				iface.encodeFunctionData("openPositionFarm", [
					0,
					ICHI,
					USDC,
					depositAmount,
					borrowAmount,
					ICHI_VAULT_PID // ICHI/USDC Vault Pool Id
				])
			);
		})

		it("should revert when another strategyId provided", async () => {
			const nextPosId = await bank.nextPositionId();
			await spell.addStrategy(alice.address, utils.parseUnits("2000", 18));
			await expect(bank.execute(
				nextPosId.sub(1),
				spell.address,
				iface.encodeFunctionData("reducePosition", [
					1,
					ICHI,
					depositAmount.div(2)
				])
			)).to.be.revertedWith("INCORRECT_STRATEGY_ID")
		})

		it("should revert when reducing position exceeds max LTV", async () => {
			const nextPosId = await bank.nextPositionId();
			const positionId = nextPosId.sub(1)
			const positionInfo = await bank.getPositionInfo(positionId)
			const underlyingShareAmount = positionInfo.underlyingVaultShare

			await expect(bank.execute(
				positionId,
				spell.address,
				iface.encodeFunctionData("reducePosition", [
					0,
					ICHI,
					underlyingShareAmount
				])
			)).to.be.revertedWith("EXCEED_MAX_LTV")
		})

		it("should be able to reduce position within maxLTV", async () => {
			const nextPosId = await bank.nextPositionId();

			await bank.execute(
				nextPosId.sub(1),
				spell.address,
				iface.encodeFunctionData("reducePosition", [
					0,
					ICHI,
					depositAmount.div(3)
				])
			)
		})

		it("should be able to increase position", async () => {
			const nextPosId = await bank.nextPositionId();

			await bank.execute(
				nextPosId.sub(1),
				spell.address,
				iface.encodeFunctionData("increasePosition", [
					ICHI,
					depositAmount.div(3)
				])
			)
		})

		it("should be able to maintain the position with more deposits/borrows", async () => {
			const nextPosId = await bank.nextPositionId();
			await bank.execute(
				nextPosId.sub(1),
				spell.address,
				iface.encodeFunctionData("openPositionFarm", [
					0,
					ICHI,
					USDC,
					depositAmount,
					borrowAmount,
					ICHI_VAULT_PID // ICHI/USDC Vault Pool Id
				])
			);
		})
		it("should revert maintaining position when farming pool id does not match", async () => {
			const nextPosId = await bank.nextPositionId();
			await expect(
				bank.execute(
					nextPosId.sub(1),
					spell.address,
					iface.encodeFunctionData("openPositionFarm", [
						0,
						ICHI,
						USDC,
						depositAmount,
						borrowAmount,
						ICHI_VAULT_PID + 1 // ICHI/USDC Vault Pool Id
					])
				)
			).to.be.revertedWith("INCORRECT_LP");
		})
	})

	describe("Owner Functions", () => {
		let spell: IchiSpell;
		const maxPosSize = utils.parseEther("200000");

		beforeEach(async () => {
			const IchiSpell = await ethers.getContractFactory(CONTRACT_NAMES.IchiSpell);
			spell = <IchiSpell>await upgrades.deployProxy(IchiSpell, [
				bank.address,
				werc20.address,
				WETH,
				wichi.address
			])
			await spell.deployed();
		})

		describe("Add Strategy", () => {
			it("only owner should be able to add new strategies to the spell", async () => {
				await expect(
					spell.connect(alice).addStrategy(ichiVault.address, maxPosSize)
				).to.be.revertedWith("Ownable: caller is not the owner")
			})
			it("should revert when vault address or maxPosSize is zero", async () => {
				await expect(
					spell.addStrategy(ethers.constants.AddressZero, maxPosSize)
				).to.be.revertedWith("ZERO_ADDRESS")
				await expect(
					spell.addStrategy(ichiVault.address, 0)
				).to.be.revertedWith("ZERO_AMOUNT")
			})
			it("owner should be able to add strategy", async () => {
				await expect(
					spell.addStrategy(ichiVault.address, maxPosSize)
				).to.be.emit(spell, "StrategyAdded").withArgs(
					0, ichiVault.address, maxPosSize
				)
			})
		})

		describe("Add Collaterals", () => {
			beforeEach(async () => {
				await spell.addStrategy(ichiVault.address, maxPosSize);
			})
			it("only owner should be able to add collaterals", async () => {
				await expect(
					spell.connect(alice).setCollateralsMaxLTVs(
						0,
						[USDC, ICHI],
						[30000, 30000]
					)
				).to.be.revertedWith("Ownable: caller is not the owner");
			})
			it("should revert when adding collaterals for non-existing strategy", async () => {
				await expect(
					spell.setCollateralsMaxLTVs(
						1,
						[USDC, ICHI],
						[30000, 30000]
					)
				).to.be.revertedWith("STRATEGY_NOT_EXIST");
			})
			it("should revert when collateral or maxLTV is zero", async () => {
				await expect(
					spell.setCollateralsMaxLTVs(
						0,
						[ethers.constants.AddressZero, ICHI],
						[30000, 30000]
					)
				).to.be.revertedWith("ZERO_ADDRESS");
				await expect(
					spell.setCollateralsMaxLTVs(
						0,
						[USDC, ICHI],
						[0, 30000]
					)
				).to.be.revertedWith("ZERO_AMOUNT");
			})
			it("should revert when input array length does not match", async () => {
				await expect(
					spell.setCollateralsMaxLTVs(
						0,
						[USDC, ICHI, WETH],
						[30000, 30000]
					)
				).to.be.revertedWith("INPUT_ARRAY_MISMATCH")
				await expect(
					spell.setCollateralsMaxLTVs(
						0,
						[],
						[]
					)
				).to.be.revertedWith("INPUT_ARRAY_MISMATCH")
			})
			it("owner should be able to add collaterals", async () => {
				await expect(
					spell.setCollateralsMaxLTVs(
						0,
						[USDC, ICHI],
						[30000, 30000]
					)
				).to.be.emit(spell, "CollateralsMaxLTVSet")
			})
		})
	})
})