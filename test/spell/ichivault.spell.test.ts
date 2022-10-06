import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai, { expect } from 'chai';
import { BigNumber, utils } from 'ethers';
import { ethers } from 'hardhat';
import {
	BlueBerryBank,
	CoreOracle,
	ERC20,
	ICErc20,
	IchiVaultSpell,
	IUniswapV2Router02,
	IWETH,
	SafeBox,
	SimpleOracle,
	IchiLpOracle,
	IIchiFarm,
	WERC20,
	WIchiFarm
} from '../../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../../constants';
import ERC20ABI from '../../abi/ERC20.json'
import ICrc20ABI from '../../abi/ICErc20.json'
import SpellABI from '../../abi/IchiVaultSpell.json';
import IchiFarmABI from '../../abi/IIchiFarm.json';

import { solidity } from 'ethereum-waffle'
import { near } from '../assertions/near'
import { roughlyNear } from '../assertions/roughlyNear'

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

describe('ICHI Angel Vaults Spell', () => {
	let admin: SignerWithAddress;
	let alice: SignerWithAddress;

	let usdc: ERC20;
	let weth: IWETH;
	let cUSDC: ICErc20;
	let werc20: WERC20;
	let simpleOracle: SimpleOracle;
	let ichiOracle: IchiLpOracle;
	let oracle: CoreOracle;
	let spell: IchiVaultSpell;
	let wichi: WIchiFarm;
	let bank: BlueBerryBank;
	let safeBox: SafeBox;
	let ichiFarm: IIchiFarm;

	before(async () => {
		[admin, alice] = await ethers.getSigners();
		usdc = <ERC20>await ethers.getContractAt(ERC20ABI, USDC, admin);
		weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);
		cUSDC = <ICErc20>await ethers.getContractAt(ICrc20ABI, CUSDC);

		const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
		werc20 = <WERC20>await WERC20.deploy();
		await werc20.deployed();

		const SimpleOracle = await ethers.getContractFactory(CONTRACT_NAMES.SimpleOracle);
		simpleOracle = <SimpleOracle>await SimpleOracle.deploy();
		await simpleOracle.deployed();
		await simpleOracle.setPrice(
			[WETH, USDC, ICHI],
			[
				BigNumber.from(10).pow(18).mul(ETH_PRICE),
				BigNumber.from(10).pow(18), // $1
				BigNumber.from(10).pow(18).mul(5), // $5
			],
		)

		const IchiLpOracle = await ethers.getContractFactory(CONTRACT_NAMES.IchiLpOracle);
		ichiOracle = <IchiLpOracle>await IchiLpOracle.deploy(simpleOracle.address);
		await ichiOracle.deployed();

		const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
		oracle = <CoreOracle>await CoreOracle.deploy();
		await oracle.deployed();

		await oracle.setWhitelistERC1155([werc20.address, ICHI_VAULT], true);
		await oracle.setTokenSettings(
			[WETH, USDC, ICHI, ICHI_VAULT],
			[{
				liqThreshold: 9000,
				route: simpleOracle.address,
			}, {
				liqThreshold: 8000,
				route: simpleOracle.address,
			}, {
				liqThreshold: 9000,
				route: simpleOracle.address,
			}, {
				liqThreshold: 10000,
				route: ichiOracle.address,
			}]
		)

		// Deploy Bank
		const BlueBerryBank = await ethers.getContractFactory(CONTRACT_NAMES.BlueBerryBank);
		bank = <BlueBerryBank>await BlueBerryBank.deploy();
		await bank.deployed();
		await bank.initialize(oracle.address, 2000);

		// Deploy ICHI wrapper and spell
		ichiFarm = <IIchiFarm>await ethers.getContractAt(IchiFarmABI, ADDRESS.ICHI_FARMING);
		const WIchiFarm = await ethers.getContractFactory(CONTRACT_NAMES.WIchiFarm);
		wichi = <WIchiFarm>await WIchiFarm.deploy(ADDRESS.ICHI, ADDRESS.ICHI_FARMING);
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
		await bank.setWhitelistSpells(
			[spell.address],
			[true]
		)
		await bank.setWhitelistTokens([USDC], [true]);

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
		safeBox = <SafeBox>await SafeBox.deploy(
			CUSDC,
			"Interest Bearing USDC",
			"ibUSDC"
		)
		await safeBox.deployed();
		await safeBox.setBank(bank.address);
		await bank.addBank(USDC, CUSDC, safeBox.address);

		await usdc.approve(safeBox.address, ethers.constants.MaxUint256);
		await safeBox.deposit(utils.parseUnits("10000", 6));
	})

	beforeEach(async () => {
	})

	it("should be able to deposit USDC on ICHI angel vault", async () => {
		const iface = new ethers.utils.Interface(SpellABI);
		await usdc.approve(bank.address, ethers.constants.MaxUint256);
		await bank.execute(
			0,
			spell.address,
			iface.encodeFunctionData("openPosition", [
				USDC,
				utils.parseUnits('100', 6),
				utils.parseUnits('300', 6)
			])
		)

		expect(await bank.nextPositionId()).to.be.equal(BigNumber.from(2));
		const pos = await bank.getPositionInfo(1);
		expect(pos.owner).to.be.equal(admin.address);
		expect(pos.collToken).to.be.equal(werc20.address);
		expect(pos.collId).to.be.equal(BigNumber.from(ICHI_VAULT));
		expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;
		expect(
			await werc20.balanceOf(bank.address, BigNumber.from(ICHI_VAULT))
		).to.be.equal(pos.collateralSize);
		const bankInfo = await bank.banks(USDC);
		console.log('Bank Info', bankInfo);
		console.log('Position Info', pos);
	})
	it("should be able to return position risk ratio", async () => {
		await bank.getPositionRisk(1);
		await simpleOracle.setPrice(
			[USDC, ICHI],
			[
				BigNumber.from(10).pow(18), // $1
				BigNumber.from(10).pow(17).mul(40), // $4
			]
		);
		const risk = await bank.getPositionRisk(1);
		console.log('Position Risk', utils.formatUnits(risk, 2), '%');
	})
	it("should be able to withdraw USDC", async () => {
		const iface = new ethers.utils.Interface(SpellABI);
		const beforeBalance = await usdc.balanceOf(admin.address);
		await bank.execute(
			1,
			spell.address,
			iface.encodeFunctionData("closePosition", [
				USDC, // ICHI vault lp token is collateral
				ethers.constants.MaxUint256,	// Amount of werc20
				ethers.constants.MaxUint256,  // Amount of 
				0,
				ethers.constants.MaxUint256,
			])
		)
		const afterBalance = await usdc.balanceOf(admin.address);
		console.log('Balance Change:', afterBalance.sub(beforeBalance));
		await safeBox.withdraw(utils.parseUnits("10000", 6));
	})

	it("should be able to farm USDC on ICHI angel vault", async () => {
		const iface = new ethers.utils.Interface(SpellABI);
		await usdc.approve(bank.address, ethers.constants.MaxUint256);
		await bank.execute(
			0,
			spell.address,
			iface.encodeFunctionData("openPositionFarm", [
				USDC,
				utils.parseUnits('100', 6),
				utils.parseUnits('200', 6),
				ICHI_VAULT_PID // ICHI/USDC Vault Pool Id
			])
		)

		expect(await bank.nextPositionId()).to.be.equal(BigNumber.from(3));
		const pos = await bank.getPositionInfo(2);
		expect(pos.owner).to.be.equal(admin.address);
		expect(pos.collToken).to.be.equal(wichi.address);
		const poolInfo = await ichiFarm.poolInfo(ICHI_VAULT_PID);
		const collId = await wichi.encodeId(ICHI_VAULT_PID, poolInfo.accIchiPerShare);
		expect(pos.collId).to.be.equal(collId);
		expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;
		expect(
			await wichi.balanceOf(bank.address, collId)
		).to.be.equal(pos.collateralSize);
	})
	it("should be able to harvest on ICHI farming", async () => {
		console.log(await usdc.balanceOf(admin.address));
		const iface = new ethers.utils.Interface(SpellABI);
		await bank.execute(
			2,
			spell.address,
			iface.encodeFunctionData("closePositionFarm", [
				USDC, // ICHI vault lp token is collateral
				ethers.constants.MaxUint256,	// Amount of werc20
				ethers.constants.MaxUint256,  // Amount of 
				0,
				ethers.constants.MaxUint256,
			])
		)
		await safeBox.withdraw(utils.parseUnits("10000", 6));
		console.log(await usdc.balanceOf(admin.address));
	})
})