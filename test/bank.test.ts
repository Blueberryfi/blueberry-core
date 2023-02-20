import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai, { expect } from 'chai';
import { BigNumber, constants, utils } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import {
	BlueBerryBank,
	CoreOracle,
	IchiVaultSpell,
	IWETH,
	SoftVault,
	MockOracle,
	IchiLpOracle,
	WERC20,
	WIchiFarm,
	ProtocolConfig,
	MockIchiVault,
	ERC20,
	MockIchiV2,
	MockIchiFarm,
	HardVault
} from '../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../constant';
import SpellABI from '../abi/IchiVaultSpell.json';

import { solidity } from 'ethereum-waffle'
import { near } from './assertions/near'
import { roughlyNear } from './assertions/roughlyNear'
import { Protocol, setupProtocol } from './setup-test';

chai.use(solidity)
chai.use(near)
chai.use(roughlyNear)

const CUSDC = ADDRESS.bUSDC;
const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const ICHI = ADDRESS.ICHI;
const ICHIV1 = ADDRESS.ICHI_FARM;
const ICHI_VAULT_PID = 0; // ICHI/USDC Vault PoolId

describe('Bank', () => {
	let admin: SignerWithAddress;
	let alice: SignerWithAddress;
	let treasury: SignerWithAddress;

	let usdc: ERC20;
	let ichi: MockIchiV2;
	let ichiV1: ERC20;
	let weth: IWETH;
	let werc20: WERC20;
	let mockOracle: MockOracle;
	let ichiOracle: IchiLpOracle;
	let oracle: CoreOracle;
	let spell: IchiVaultSpell;
	let wichi: WIchiFarm;
	let bank: BlueBerryBank;
	let config: ProtocolConfig;
	let usdcSoftVault: SoftVault;
	let ichiSoftVault: SoftVault;
	let hardVault: HardVault;
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
		config = protocol.config;
		bank = protocol.bank;
		spell = protocol.spell;
		ichiFarm = protocol.ichiFarm;
		ichiVault = protocol.ichi_USDC_ICHI_Vault;
		wichi = protocol.wichi;
		werc20 = protocol.werc20;
		oracle = protocol.oracle;
		mockOracle = protocol.mockOracle;
		usdcSoftVault = protocol.usdcSoftVault;
		ichiSoftVault = protocol.ichiSoftVault;
		hardVault = protocol.hardVault;
	})

	beforeEach(async () => {
	})

	describe("Constructor", () => {
		it("should revert Bank deployment when invalid args provided", async () => {
			const BlueBerryBank = await ethers.getContractFactory(CONTRACT_NAMES.BlueBerryBank);
			await expect(
				upgrades.deployProxy(BlueBerryBank, [ethers.constants.AddressZero, config.address])
			).to.be.revertedWith("ZERO_ADDRESS");

			await expect(
				upgrades.deployProxy(BlueBerryBank, [oracle.address, ethers.constants.AddressZero])
			).to.be.revertedWith("ZERO_ADDRESS");
		})
		it("should initialize states on constructor", async () => {
			const BlueBerryBank = await ethers.getContractFactory(CONTRACT_NAMES.BlueBerryBank);
			const bank = <BlueBerryBank>await upgrades.deployProxy(BlueBerryBank, [oracle.address, config.address]);
			await bank.deployed();

			expect(await bank._GENERAL_LOCK()).to.be.equal(1);
			expect(await bank._IN_EXEC_LOCK()).to.be.equal(1);
			expect(await bank.POSITION_ID()).to.be.equal(ethers.constants.MaxUint256);
			expect(await bank.SPELL()).to.be.equal("0x0000000000000000000000000000000000000001");
			expect(await bank.oracle()).to.be.equal(oracle.address);
			expect(await bank.config()).to.be.equal(config.address);
			expect(await bank.nextPositionId()).to.be.equal(1);
			expect(await bank.bankStatus()).to.be.equal(7);
		})
	})

	describe("Liquidation", () => {
		const depositAmount = utils.parseUnits('100', 18); // worth of $400
		const borrowAmount = utils.parseUnits('300', 6);
		const iface = new ethers.utils.Interface(SpellABI);

		beforeEach(async () => {
			await usdc.approve(bank.address, ethers.constants.MaxUint256);
			await ichi.approve(bank.address, ethers.constants.MaxUint256);
			await bank.execute(
				0,
				spell.address,
				iface.encodeFunctionData("openPosition", [
					0,
					ICHI,
					USDC,
					depositAmount,
					borrowAmount // 3x
				])
			)
		})
		it("should be able to liquidate the position => (OV - PV)/CV = LT", async () => {
			const positionIds = await bank.getPositionIdsByOwner(admin.address);
			console.log(positionIds);
			await ichiVault.rebalance(-260400, -260200, -260800, -260600, 0);
			let positionInfo = await bank.getPositionInfo(1);
			let debtValue = await bank.getDebtValue(1)
			let positionValue = await bank.getPositionValue(1);
			let risk = await bank.getPositionRisk(1)
			console.log("Debt Value:", utils.formatUnits(debtValue));
			console.log("Position Value:", utils.formatUnits(positionValue));
			console.log('Position Risk:', utils.formatUnits(risk, 2), '%');
			console.log("Position Size:", utils.formatUnits(positionInfo.collateralSize));

			console.log('===ICHI token dumped from $5 to $1===');
			await mockOracle.setPrice(
				[ICHI],
				[
					BigNumber.from(10).pow(17).mul(10), // $0.5
				]
			);
			positionInfo = await bank.getPositionInfo(1);
			debtValue = await bank.getDebtValue(1)
			positionValue = await bank.getPositionValue(1);
			risk = await bank.getPositionRisk(1)
			console.log("Cur Pos:", positionInfo);
			console.log("Debt Value:", utils.formatUnits(debtValue));
			console.log("Position Value:", utils.formatUnits(positionValue));
			console.log('Position Risk:', utils.formatUnits(risk, 2), '%');
			console.log("Position Size:", utils.formatUnits(positionInfo.collateralSize));

			expect(await bank.isLiquidatable(1)).to.be.true;
			console.log("Is Liquidatable:", await bank.isLiquidatable(1));

			console.log("===Portion Liquidated===");
			const liqAmount = utils.parseUnits("100", 6);
			await usdc.connect(alice).approve(bank.address, liqAmount)
			await expect(
				bank.connect(alice).liquidate(1, USDC, liqAmount)
			).to.be.emit(bank, "Liquidate");

			positionInfo = await bank.getPositionInfo(1);
			debtValue = await bank.getDebtValue(1)
			positionValue = await bank.getPositionValue(1);
			risk = await bank.getPositionRisk(1)
			console.log("Cur Pos:", positionInfo);
			console.log("Debt Value:", utils.formatUnits(debtValue));
			console.log("Position Value:", utils.formatUnits(positionValue));
			console.log('Position Risk:', utils.formatUnits(risk, 2), '%');
			console.log("Position Size:", utils.formatUnits(positionInfo.collateralSize));

			const colToken = await ethers.getContractAt("ERC1155Upgradeable", positionInfo.collToken);
			const uVToken = await ethers.getContractAt("ERC20Upgradeable", ichiSoftVault.address);
			console.log("Liquidator's Position Balance:", await colToken.balanceOf(alice.address, positionInfo.collId));
			console.log("Liquidator's Collateral Balance:", await uVToken.balanceOf(alice.address));

			console.log("===Full Liquidate===");
			await usdc.connect(alice).approve(bank.address, ethers.constants.MaxUint256)
			await expect(
				bank.connect(alice).liquidate(1, USDC, ethers.constants.MaxUint256)
			).to.be.emit(bank, "Liquidate");

			positionInfo = await bank.getPositionInfo(1);
			debtValue = await bank.getDebtValue(1)
			positionValue = await bank.getPositionValue(1);
			risk = await bank.getPositionRisk(1)
			console.log("Cur Pos:", positionInfo);
			console.log("Debt Value:", utils.formatUnits(debtValue));
			console.log("Position Value:", utils.formatUnits(positionValue));
			console.log('Position Risk:', utils.formatUnits(risk, 2), '%');
			console.log("Position Size:", utils.formatUnits(positionInfo.collateralSize));
			console.log("Liquidator's Position Balance:", await colToken.balanceOf(alice.address, positionInfo.collId));
			console.log("Liquidator's Collateral Balance:", await uVToken.balanceOf(alice.address));
		})
	})

	describe("Mics", () => {
		describe("Owner", () => {
			it("should be able to allow contract calls", async () => {
				await expect(
					bank.connect(alice).setAllowContractCalls(true)
				).to.be.revertedWith('Ownable: caller is not the owner')

				await bank.setAllowContractCalls(true);
				expect(await bank.allowContractCalls()).be.true;
			})
			it("should be able to whitelist contracts for bank execution", async () => {
				await expect(
					bank.connect(alice).whitelistContracts([admin.address, alice.address], [true, true])
				).to.be.revertedWith('Ownable: caller is not the owner')
				await expect(
					bank.whitelistContracts([admin.address], [true, true])
				).to.be.revertedWith('INPUT_ARRAY_MISMATCH');

				await expect(
					bank.whitelistContracts([admin.address, constants.AddressZero], [true, true])
				).to.be.revertedWith('ZERO_ADDRESS');

				expect(await bank.whitelistedContracts(admin.address)).to.be.false;
				await bank.whitelistContracts([admin.address], [true]);
				expect(await bank.whitelistedContracts(admin.address)).to.be.true;
			})
			it("should be able to whitelist spells", async () => {
				await expect(
					bank.connect(alice).whitelistSpells([admin.address, alice.address], [true, true])
				).to.be.revertedWith('Ownable: caller is not the owner')
				await expect(
					bank.whitelistSpells([admin.address], [true, true])
				).to.be.revertedWith('INPUT_ARRAY_MISMATCH');

				await expect(
					bank.whitelistSpells([admin.address, constants.AddressZero], [true, true])
				).to.be.revertedWith('ZERO_ADDRESS');

				expect(await bank.whitelistedSpells(admin.address)).to.be.false;
				await bank.whitelistSpells([admin.address], [true]);
				expect(await bank.whitelistedSpells(admin.address)).to.be.true;
			})
			it("should be able to whitelist tokens", async () => {
				await expect(
					bank.connect(alice).whitelistTokens([WETH], [true])
				).to.be.revertedWith("Ownable: caller is not the owner");

				await expect(
					bank.whitelistTokens([WETH, ICHI], [true])
				).to.be.revertedWith("INPUT_ARRAY_MISMATCH");

				await expect(
					bank.whitelistTokens([ADDRESS.CRV], [true])
				).to.be.revertedWith("");
			})
			it("should be able to add bank", async () => {
				await expect(
					bank.connect(alice).addBank(USDC, usdcSoftVault.address, hardVault.address)
				).to.be.revertedWith("Ownable: caller is not the owner");

				await expect(
					bank.addBank(ethers.constants.AddressZero, usdcSoftVault.address, hardVault.address)
				).to.be.revertedWith("TOKEN_NOT_WHITELISTED");
				await expect(
					bank.addBank(USDC, ethers.constants.AddressZero, hardVault.address)
				).to.be.revertedWith("ZERO_ADDRESS");
				await expect(
					bank.addBank(USDC, usdcSoftVault.address, ethers.constants.AddressZero)
				).to.be.revertedWith("ZERO_ADDRESS");

				await expect(
					bank.addBank(USDC, usdcSoftVault.address, hardVault.address)
				).to.be.revertedWith("CTOKEN_ALREADY_ADDED");
			})
			it("should be able to set bank status", async () => {
				let bankStatus = await bank.bankStatus();
				await expect(
					bank.connect(alice).setBankStatus(0)
				).to.be.revertedWith("Ownable: caller is not the owner");

				await bank.setBankStatus(0);
				expect(await bank.isBorrowAllowed()).to.be.false;
				expect(await bank.isRepayAllowed()).to.be.false;
				expect(await bank.isLendAllowed()).to.be.false;

				const iface = new ethers.utils.Interface(SpellABI);
				const depositAmount = utils.parseUnits('100', 18);
				const borrowAmount = utils.parseUnits('300', 6);
				await ichi.approve(bank.address, ethers.constants.MaxUint256);

				await expect(
					bank.execute(
						0,
						spell.address,
						iface.encodeFunctionData("openPosition", [
							0,
							ICHI,
							USDC,
							depositAmount,
							borrowAmount // 3x
						])
					)
				).to.be.revertedWith("LEND_NOT_ALLOWED");

				await bank.setBankStatus(4);
				expect(await bank.isBorrowAllowed()).to.be.false;
				expect(await bank.isRepayAllowed()).to.be.false;
				expect(await bank.isLendAllowed()).to.be.true;

				await expect(
					bank.execute(
						0,
						spell.address,
						iface.encodeFunctionData("openPosition", [
							0,
							ICHI,
							USDC,
							depositAmount,
							borrowAmount // 3x
						])
					)
				).to.be.revertedWith("BORROW_NOT_ALLOWED");

				await bank.setBankStatus(7);
			})
		})
		describe("Accrue", () => {
			it("anyone can call accrue functions by tokens", async () => {
				await expect(
					bank.accrue(ADDRESS.WETH)
				).to.be.revertedWith("BANK_NOT_LISTED");

				await bank.accrueAll([USDC, ICHI]);
			})
		})
		describe("View functions", async () => {
			it("should revert EXECUTOR call when the bank is not under execution", async () => {
				await expect(bank.EXECUTOR()).to.be.revertedWith("NOT_UNDER_EXECUTION");
			})
			it("should be able to check if the oracle support the token", async () => {
				expect(await oracle.support(ADDRESS.CRV)).to.be.false;
				expect(await bank.support(ADDRESS.CRV)).to.be.false;
				expect(await bank.support(ADDRESS.USDC)).to.be.true;
			})
		})
	})

})