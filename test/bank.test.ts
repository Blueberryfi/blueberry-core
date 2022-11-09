import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai, { expect } from 'chai';
import { BigNumber, constants, utils } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import {
	BlueBerryBank,
	CoreOracle,
	ERC20,
	ICErc20,
	IchiVaultSpell,
	IUniswapV2Router02,
	IWETH,
	SafeBox,
	MockOracle,
	IchiLpOracle,
	IIchiFarm,
	WERC20,
	WIchiFarm,
	ProtocolConfig
} from '../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../constant';
import ERC20ABI from '../abi/ERC20.json'
import ICrc20ABI from '../abi/ICErc20.json'
import SpellABI from '../abi/IchiVaultSpell.json';
import IchiFarmABI from '../abi/IIchiFarm.json';

import { solidity } from 'ethereum-waffle'
import { near } from './assertions/near'
import { roughlyNear } from './assertions/roughlyNear'
import { evm_mine_blocks } from './helpers';

chai.use(solidity)
chai.use(near)
chai.use(roughlyNear)

const CUSDC = ADDRESS.cyUSDC;			// IronBank cyUSDC
const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const ICHI = ADDRESS.ICHI;
const ICHI_VAULT = ADDRESS.ICHI_VAULT_USDC;
const ICHI_VAULT_PID = 27; // ICHI/USDC Vault PoolId
const ETH_PRICE = 1600;

describe('Bank', () => {
	let admin: SignerWithAddress;
	let alice: SignerWithAddress;
	let treasury: SignerWithAddress;

	let usdc: ERC20;
	let weth: IWETH;
	let cUSDC: ICErc20;
	let werc20: WERC20;
	let mockOracle: MockOracle;
	let ichiOracle: IchiLpOracle;
	let oracle: CoreOracle;
	let spell: IchiVaultSpell;
	let wichi: WIchiFarm;
	let bank: BlueBerryBank;
	let config: ProtocolConfig;
	let safeBox: SafeBox;
	let ichiFarm: IIchiFarm;

	before(async () => {
		[admin, alice, treasury] = await ethers.getSigners();
		usdc = <ERC20>await ethers.getContractAt(ERC20ABI, USDC, admin);
		weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);
		cUSDC = <ICErc20>await ethers.getContractAt(ICrc20ABI, CUSDC);

		const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
		werc20 = <WERC20>await upgrades.deployProxy(WERC20);
		await werc20.deployed();

		const MockOracle = await ethers.getContractFactory(CONTRACT_NAMES.MockOracle);
		mockOracle = <MockOracle>await MockOracle.deploy();
		await mockOracle.deployed();
		await mockOracle.setPrice(
			[WETH, USDC, ICHI],
			[
				BigNumber.from(10).pow(18).mul(ETH_PRICE),
				BigNumber.from(10).pow(18), // $1
				BigNumber.from(10).pow(18).mul(5), // $5
			],
		)

		const IchiLpOracle = await ethers.getContractFactory(CONTRACT_NAMES.IchiLpOracle);
		ichiOracle = <IchiLpOracle>await IchiLpOracle.deploy(mockOracle.address);
		await ichiOracle.deployed();

		const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
		oracle = <CoreOracle>await CoreOracle.deploy();
		await oracle.deployed();

		await oracle.setWhitelistERC1155([werc20.address, ICHI_VAULT], true);
		await oracle.setTokenSettings(
			[WETH, USDC, ICHI, ICHI_VAULT],
			[{
				liqThreshold: 9000,
				route: mockOracle.address,
			}, {
				liqThreshold: 8000,
				route: mockOracle.address,
			}, {
				liqThreshold: 9000,
				route: mockOracle.address,
			}, {
				liqThreshold: 10000,
				route: ichiOracle.address,
			}]
		)

		// Deploy Bank
		const Config = await ethers.getContractFactory("ProtocolConfig");
		config = <ProtocolConfig>await upgrades.deployProxy(Config, [treasury.address]);

		const BlueBerryBank = await ethers.getContractFactory(CONTRACT_NAMES.BlueBerryBank);
		bank = <BlueBerryBank>await upgrades.deployProxy(BlueBerryBank, [oracle.address, config.address, 2000]);
		await bank.deployed();

		// Deploy ICHI wrapper and spell
		ichiFarm = <IIchiFarm>await ethers.getContractAt(IchiFarmABI, ADDRESS.ICHI_FARMING);
		const WIchiFarm = await ethers.getContractFactory(CONTRACT_NAMES.WIchiFarm);
		wichi = <WIchiFarm>await upgrades.deployProxy(WIchiFarm, [ADDRESS.ICHI, ADDRESS.ICHI_FARMING]);
		await wichi.deployed();

		const ICHISpell = await ethers.getContractFactory(CONTRACT_NAMES.IchiVaultSpell);
		spell = <IchiVaultSpell>await ICHISpell.deploy(
			bank.address,
			werc20.address,
			weth.address,
			wichi.address
		)
		await spell.deployed();
		await spell.addVault(USDC, ICHI_VAULT);
		await spell.setWhitelistLPTokens([ICHI_VAULT], [true]);
		await oracle.setWhitelistERC1155([wichi.address], true);

		// Setup Bank
		await bank.whitelistSpells(
			[spell.address],
			[true]
		)
		await bank.whitelistTokens([USDC], [true]);

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

		// Deposit 10k USDC to compound
		const SafeBox = await ethers.getContractFactory(CONTRACT_NAMES.SafeBox);
		safeBox = <SafeBox>await upgrades.deployProxy(SafeBox, [
			CUSDC,
			"Interest Bearing USDC",
			"ibUSDC"
		])
		await safeBox.deployed();
		await safeBox.setBank(bank.address);
		await bank.addBank(USDC, CUSDC, safeBox.address);

		await usdc.approve(safeBox.address, ethers.constants.MaxUint256);
		await usdc.transfer(alice.address, utils.parseUnits("500", 6));
		await safeBox.deposit(utils.parseUnits("10000", 6));
	})

	beforeEach(async () => {
	})

	describe("Constructor", () => {
		it("should revert Bank deployment when invalid args provided", async () => {
			const BlueBerryBank = await ethers.getContractFactory(CONTRACT_NAMES.BlueBerryBank);
			await expect(
				upgrades.deployProxy(BlueBerryBank, [ethers.constants.AddressZero, config.address, 2000])
			).to.be.revertedWith("ZERO_ADDRESS");

			await expect(
				upgrades.deployProxy(BlueBerryBank, [oracle.address, ethers.constants.AddressZero, 2000])
			).to.be.revertedWith("ZERO_ADDRESS");

			await expect(
				upgrades.deployProxy(BlueBerryBank, [oracle.address, config.address, 10001])
			).to.be.revertedWith("FEE_TOO_HIGH(10001)");
		})
		it("should initialize states on constructor", async () => {
			const BlueBerryBank = await ethers.getContractFactory(CONTRACT_NAMES.BlueBerryBank);
			const bank = <BlueBerryBank>await upgrades.deployProxy(BlueBerryBank, [oracle.address, config.address, 2000]);
			await bank.deployed();

			expect(await bank._GENERAL_LOCK()).to.be.equal(1);
			expect(await bank._IN_EXEC_LOCK()).to.be.equal(1);
			expect(await bank.POSITION_ID()).to.be.equal(ethers.constants.MaxUint256);
			expect(await bank.SPELL()).to.be.equal("0x0000000000000000000000000000000000000001");
			expect(await bank.oracle()).to.be.equal(oracle.address);
			expect(await bank.config()).to.be.equal(config.address);
			expect(await bank.feeBps()).to.be.equal(2000);
			expect(await bank.nextPositionId()).to.be.equal(1);
			expect(await bank.bankStatus()).to.be.equal(7);
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
			it("should be able to set oracle address", async () => {
				await bank.setOracle(admin.address);
				await expect(
					bank.connect(alice).setOracle(oracle.address)
				).to.be.revertedWith('Ownable: caller is not the owner');

				await expect(
					bank.setOracle(constants.AddressZero)
				).to.be.revertedWith('ZERO_ADDRESS');

				await expect(
					bank.setOracle(oracle.address)
				).to.be.emit(bank, "SetOracle").withArgs(oracle.address)
				expect(await bank.oracle()).to.be.equal(oracle.address);
			})
			it("should be able to set fee bps", async () => {
				await expect(
					bank.connect(alice).setFeeBps(2000)
				).to.be.revertedWith('Ownable: caller is not the owner');

				await expect(
					bank.setFeeBps(10001)
				).to.be.revertedWith('FEE_TOO_HIGH(10001)');

				await expect(
					bank.setFeeBps(2000)
				).to.be.emit(bank, "SetFeeBps").withArgs(2000)
				expect(await bank.feeBps()).to.be.equal(2000);
			})
			it("should be able to update SafeBox address", async () => {
				let bankInfo = await bank.banks(USDC);
				expect(bankInfo.isListed).to.be.true;
				await expect(
					bank.connect(alice).updateSafeBox(USDC, safeBox.address)
				).to.be.revertedWith('Ownable: caller is not the owner');

				await expect(
					bank.updateSafeBox(constants.AddressZero, safeBox.address)
				).to.be.revertedWith('BANK_NOT_LISTED');

				await expect(
					bank.updateSafeBox(USDC, constants.AddressZero)
				).to.be.revertedWith('ZERO_ADDRESS');

				await bank.updateSafeBox(USDC, safeBox.address);
				bankInfo = await bank.banks(USDC);
				expect(bankInfo.safeBox).to.be.equal(safeBox.address);
			})
		})

		it("should revert EXECUTOR call when the bank is not under execution", async () => {
			await expect(bank.EXECUTOR()).to.be.revertedWith("NOT_UNDER_EXECUTION");
		})
	})

	describe("Liquidation", () => {
		beforeEach(async () => {
			const iface = new ethers.utils.Interface(SpellABI);
			await usdc.approve(bank.address, ethers.constants.MaxUint256);
			await bank.execute(
				0,
				spell.address,
				iface.encodeFunctionData("openPosition", [
					USDC,
					utils.parseUnits('100', 6),
					utils.parseUnits('300', 6) // 3x
				])
			)
		})
		it("should be able to liquidate the position => (OV - PV)/CV = LT", async () => {
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
					BigNumber.from(10).pow(17).mul(10), // $1
				]
			);
			positionInfo = await bank.getPositionInfo(1);
			debtValue = await bank.getDebtValue(1)
			positionValue = await bank.getPositionValue(1);
			risk = await bank.getPositionRisk(1)
			console.log("Debt Value:", utils.formatUnits(debtValue));
			console.log("Position Value:", utils.formatUnits(positionValue));
			console.log('Position Risk:', utils.formatUnits(risk, 2), '%');
			console.log("Position Size:", utils.formatUnits(positionInfo.collateralSize));

			expect(await bank.isLiquidatable(1)).to.be.true;

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
			console.log("Debt Value:", utils.formatUnits(debtValue));
			console.log("Position Value:", utils.formatUnits(positionValue));
			console.log('Position Risk:', utils.formatUnits(risk, 2), '%');
			console.log("Position Size:", utils.formatUnits(positionInfo.collateralSize));

			const colToken = await ethers.getContractAt("ERC1155", positionInfo.collToken);
			console.log("Liquidator's Position Balance:", await colToken.balanceOf(alice.address, positionInfo.collId));

			console.log("===Full Liquidate===");
			await usdc.connect(alice).approve(bank.address, ethers.constants.MaxUint256)
			await expect(
				bank.connect(alice).liquidate(1, USDC, ethers.constants.MaxUint256)
			).to.be.emit(bank, "Liquidate");

			positionInfo = await bank.getPositionInfo(1);
			debtValue = await bank.getDebtValue(1)
			positionValue = await bank.getPositionValue(1);
			risk = await bank.getPositionRisk(1)
			console.log("Debt Value:", utils.formatUnits(debtValue));
			console.log("Position Value:", utils.formatUnits(positionValue));
			console.log('Position Risk:', utils.formatUnits(risk, 2), '%');
			console.log("Position Size:", utils.formatUnits(positionInfo.collateralSize));
			console.log("Liquidator's Position Balance:", await colToken.balanceOf(alice.address, positionInfo.collId));
		})
	})
})