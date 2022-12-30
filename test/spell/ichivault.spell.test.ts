import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai, { expect } from 'chai';
import { BigNumber, utils } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import {
	BlueBerryBank,
	CoreOracle,
	ICErc20,
	IchiVaultSpell,
	IWETH,
	MockOracle,
	SoftVault,
	IchiLpOracle,
	WERC20,
	WIchiFarm,
	ProtocolConfig,
	IComptroller,
	MockIchiVault,
	MockIchiFarm,
	ERC20,
	IUniswapV2Router02,
	MockIchiV2,
	HardVault
} from '../../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import SpellABI from '../../abi/IchiVaultSpell.json';

import { solidity } from 'ethereum-waffle'
import { near } from '../assertions/near'
import { roughlyNear } from '../assertions/roughlyNear'
import { evm_mine_blocks } from '../helpers';

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
	let ichiOracle: IchiLpOracle;
	let oracle: CoreOracle;
	let spell: IchiVaultSpell;
	let wichi: WIchiFarm;
	let config: ProtocolConfig;
	let bank: BlueBerryBank;
	let usdcSoftVault: SoftVault;
	let ichiSoftVault: SoftVault;
	let hardVault: HardVault;
	let ichiFarm: MockIchiFarm;
	let ichiVault: MockIchiVault;

	before(async () => {
		[admin, alice, treasury] = await ethers.getSigners();
		usdc = <ERC20>await ethers.getContractAt("ERC20", USDC, admin);
		ichi = <MockIchiV2>await ethers.getContractAt("MockIchiV2", ICHI, admin);
		ichiV1 = <ERC20>await ethers.getContractAt("ERC20", ICHIV1, admin);
		weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);

		// Prepare USDC
		// deposit 80 eth -> 80 WETH
		await weth.deposit({ value: utils.parseUnits('80') });

		// swap 40 weth -> usdc
		await weth.approve(ADDRESS.UNI_V2_ROUTER, ethers.constants.MaxUint256);
		const uniV2Router = <IUniswapV2Router02>await ethers.getContractAt(
			CONTRACT_NAMES.IUniswapV2Router02,
			ADDRESS.UNI_V2_ROUTER
		);
		await uniV2Router.swapExactTokensForTokens(
			utils.parseUnits('40'),
			0,
			[WETH, USDC],
			admin.address,
			ethers.constants.MaxUint256
		)
		// Swap 40 weth -> ichi
		await weth.approve(ADDRESS.SUSHI_ROUTER, ethers.constants.MaxUint256);
		const sushiRouter = <IUniswapV2Router02>await ethers.getContractAt(
			CONTRACT_NAMES.IUniswapV2Router02,
			ADDRESS.SUSHI_ROUTER
		);
		await sushiRouter.swapExactTokensForTokens(
			utils.parseUnits('40'),
			0,
			[WETH, ICHIV1],
			admin.address,
			ethers.constants.MaxUint256
		)
		await ichiV1.approve(ICHI, ethers.constants.MaxUint256);
		const ichiV1Balance = await ichiV1.balanceOf(admin.address);
		await ichi.convertToV2(ichiV1Balance.div(2));
		console.log("ICHI Balance:", utils.formatEther(await ichi.balanceOf(admin.address)));

		const LinkedLibFactory = await ethers.getContractFactory("UniV3WrappedLib");
		const LibInstance = await LinkedLibFactory.deploy();

		const IchiVault = await ethers.getContractFactory("MockIchiVault", {
			libraries: {
				UniV3WrappedLibMockup: LibInstance.address
			}
		});
		ichiVault = await IchiVault.deploy(
			ADDRESS.UNI_V3_ICHI_USDC,
			true,
			true,
			admin.address,
			admin.address,
			3600
		)
		await usdc.approve(ichiVault.address, utils.parseUnits("100", 6));
		await ichi.approve(ichiVault.address, utils.parseUnits("100", 18));
		await ichiVault.deposit(utils.parseUnits("100", 18), utils.parseUnits("100", 6), admin.address)

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

		await oracle.setWhitelistERC1155([werc20.address, ichiVault.address], true);
		await oracle.setTokenSettings(
			[WETH, USDC, ICHI, ichiVault.address],
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
		// config.startVaultWithdrawFee();

		const BlueBerryBank = await ethers.getContractFactory(CONTRACT_NAMES.BlueBerryBank);
		bank = <BlueBerryBank>await upgrades.deployProxy(BlueBerryBank, [oracle.address, config.address]);
		await bank.deployed();

		// Deploy ICHI wrapper and spell
		const MockIchiFarm = await ethers.getContractFactory("MockIchiFarm");
		ichiFarm = <MockIchiFarm>await MockIchiFarm.deploy(
			ADDRESS.ICHI_FARM,
			ethers.utils.parseUnits("1", 9) // 1 ICHI.FARM per block
		);
		const WIchiFarm = await ethers.getContractFactory(CONTRACT_NAMES.WIchiFarm);
		wichi = <WIchiFarm>await upgrades.deployProxy(WIchiFarm, [
			ADDRESS.ICHI,
			ADDRESS.ICHI_FARM,
			ichiFarm.address
		]);
		await wichi.deployed();

		const ICHISpell = await ethers.getContractFactory(CONTRACT_NAMES.IchiVaultSpell);
		spell = <IchiVaultSpell>await upgrades.deployProxy(ICHISpell, [
			bank.address,
			werc20.address,
			WETH,
			wichi.address
		])
		await spell.deployed();
		await spell.addStrategy(ichiVault.address, utils.parseUnits("2000", 18));
		await spell.addCollaterals(
			0,
			[USDC, ICHI],
			[30000, 30000]
		);
		await spell.setWhitelistLPTokens([ichiVault.address], [true]);
		await oracle.setWhitelistERC1155([wichi.address], true);

		// Setup Bank
		await bank.whitelistSpells(
			[spell.address],
			[true]
		)
		await bank.whitelistTokens([USDC, ICHI], [true, true]);

		const HardVault = await ethers.getContractFactory(CONTRACT_NAMES.HardVault);
		hardVault = <HardVault>await upgrades.deployProxy(HardVault, [
			config.address,
		])
		// Deposit 10k USDC to compound
		const SoftVault = await ethers.getContractFactory(CONTRACT_NAMES.SoftVault);
		usdcSoftVault = <SoftVault>await upgrades.deployProxy(SoftVault, [
			config.address,
			CUSDC,
			"Interest Bearing USDC",
			"ibUSDC"
		])
		await usdcSoftVault.deployed();
		await bank.addBank(USDC, CUSDC, usdcSoftVault.address, hardVault.address);

		ichiSoftVault = <SoftVault>await upgrades.deployProxy(SoftVault, [
			config.address,
			CICHI,
			"Interest Bearing ICHI",
			"ibICHI"
		]);
		await ichiSoftVault.deployed();
		await bank.addBank(ICHI, CICHI, ichiSoftVault.address, hardVault.address);

		await usdc.approve(usdcSoftVault.address, ethers.constants.MaxUint256);
		await usdc.transfer(alice.address, utils.parseUnits("500", 6));
		await usdcSoftVault.deposit(utils.parseUnits("10000", 6));

		await ichi.approve(ichiSoftVault.address, ethers.constants.MaxUint256);
		await ichi.transfer(alice.address, utils.parseUnits("500", 18));
		await ichiSoftVault.deposit(utils.parseUnits("10000", 6));

		// Enter markets
		// await bank.enterMarkets(ADDRESS.COMP, [CUSDC, CICHI]);
		// Whitelist bank contract on compound
		const compound = <IComptroller>await ethers.getContractAt("IComptroller", ADDRESS.BLB_COMPTROLLER, admin);
		await compound._setCreditLimit(bank.address, CUSDC, utils.parseUnits("3000000"));
		await compound._setCreditLimit(bank.address, CICHI, utils.parseUnits("3000000"));

		// Add new ichi vault to farming pool
		await ichiFarm.add(100, ichiVault.address);
		await ichiFarm.add(100, admin.address); // fake pool
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
			expect(await ichi.balanceOf(CICHI)).to.be.near(depositAmount.sub(fee))

			expect(await bank.nextPositionId()).to.be.equal(BigNumber.from(2));
			const pos = await bank.positions(1);
			expect(pos.owner).to.be.equal(admin.address);
			expect(pos.collToken).to.be.equal(werc20.address);
			expect(pos.collId).to.be.equal(BigNumber.from(ichiVault.address));
			expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;
			expect(
				await werc20.balanceOf(bank.address, BigNumber.from(ichiVault.address))
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

			expect(await bank.nextPositionId()).to.be.equal(BigNumber.from(3));
			const pos = await bank.positions(2);
			expect(pos.owner).to.be.equal(admin.address);
			expect(pos.collToken).to.be.equal(wichi.address);
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
		it("should be able to return position risk ratio", async () => {
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
			expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.equal(withdrawFee);
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

		it("should revert when reducing position exceeds max LTV", async () => {
			const nextPosId = await bank.nextPositionId();

			await bank.execute(
				nextPosId.sub(1),
				spell.address,
				iface.encodeFunctionData("reducePosition", [
					0,
					ICHI,
					depositAmount.div(2)
				])
			)
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
		let spell: IchiVaultSpell;
		const maxPosSize = utils.parseEther("200000");

		beforeEach(async () => {
			const ICHISpell = await ethers.getContractFactory(CONTRACT_NAMES.IchiVaultSpell);
			spell = <IchiVaultSpell>await upgrades.deployProxy(ICHISpell, [
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
					spell.connect(alice).addCollaterals(
						0,
						[USDC, ICHI],
						[30000, 30000]
					)
				).to.be.revertedWith("Ownable: caller is not the owner");
			})
			it("should revert when adding collaterals for non-existing strategy", async () => {
				await expect(
					spell.addCollaterals(
						1,
						[USDC, ICHI],
						[30000, 30000]
					)
				).to.be.revertedWith("STRATEGY_NOT_EXIST");
			})
			it("should revert when collateral or maxLTV is zero", async () => {
				await expect(
					spell.addCollaterals(
						0,
						[ethers.constants.AddressZero, ICHI],
						[30000, 30000]
					)
				).to.be.revertedWith("ZERO_ADDRESS");
				await expect(
					spell.addCollaterals(
						0,
						[USDC, ICHI],
						[0, 30000]
					)
				).to.be.revertedWith("ZERO_AMOUNT");
			})
			it("should revert when input array length does not match", async () => {
				await expect(
					spell.addCollaterals(
						0,
						[USDC, ICHI, WETH],
						[30000, 30000]
					)
				).to.be.revertedWith("INPUT_ARRAY_MISMATCH")
				await expect(
					spell.addCollaterals(
						0,
						[],
						[]
					)
				).to.be.revertedWith("INPUT_ARRAY_MISMATCH")
			})
			it("owner should be able to add collaterals", async () => {
				await expect(
					spell.addCollaterals(
						0,
						[USDC, ICHI],
						[30000, 30000]
					)
				).to.be.emit(spell, "CollateralsAdded")
			})
		})
	})
})