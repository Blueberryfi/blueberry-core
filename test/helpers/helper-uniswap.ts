import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { BigNumber, Contract, Signer } from "ethers"
import { ethers, deployments } from 'hardhat';
import { CONTRACT_NAMES } from "../../constants"
import {
	CoreOracle,
	HomoraBank,
	IERC20,
	MockERC20,
	MockUniswapV2Factory,
	MockUniswapV2Router02,
	SimpleOracle,
	UniswapV2Oracle,
	UniswapV2SpellV1,
	WERC20
} from "../../typechain-types"
import SpellArtifact from '../../artifacts/contracts/spell/UniswapV2SpellV1.sol/UniswapV2SpellV1.json';

export const setup_uniswap = async (
	admin: SignerWithAddress,
	alice: SignerWithAddress,
	bank: HomoraBank,
	werc20: WERC20,
	urouter: MockUniswapV2Router02,
	ufactory: MockUniswapV2Factory,
	usdc: MockERC20,
	usdt: MockERC20,
	simpleOracle: SimpleOracle,
	coreOracle: CoreOracle,
	oracle: Contract,
) => {
	const UniswapV2SpellV1 = await ethers.getContractFactory(CONTRACT_NAMES.UniswapV2SpellV1);
	const spell = <UniswapV2SpellV1>await UniswapV2SpellV1.deploy(
		bank.address,
		werc20.address,
		urouter.address
	);
	await spell.deployed();

	await usdc.mint(admin.address, BigNumber.from(10).pow(6).mul(10_000_000))
	await usdt.mint(admin.address, BigNumber.from(10).pow(6).mul(10_000_000))
	await usdc.approve(urouter.address, ethers.constants.MaxUint256);
	await usdt.approve(urouter.address, ethers.constants.MaxUint256);
	await urouter.addLiquidity(
		usdc.address,
		usdt.address,
		BigNumber.from(10).pow(6).mul(1_000_000),
		BigNumber.from(10).pow(6).mul(1_000_000),
		0,
		0,
		admin.address,
		ethers.constants.MaxUint256
	)

	const lp = await ufactory.getPair(usdc.address, usdt.address);
	const lpContract = <IERC20>await ethers.getContractAt(CONTRACT_NAMES.IERC20, lp);
	console.log('admin lp bal:', lpContract.balanceOf(admin.address));

	const UniswapLpOracle = await ethers.getContractFactory(CONTRACT_NAMES.UniswapV2Oracle);
	const uniswapLpOracle = <UniswapV2Oracle>await UniswapLpOracle.deploy(coreOracle.address);
	await uniswapLpOracle.deployed();

	console.log('usdt Px:', simpleOracle.getETHPx(usdt.address));
	console.log('usdc Px:', simpleOracle.getETHPx(usdc.address));

	await coreOracle.setRoute(
		[usdc.address, usdt.address, lp],
		[simpleOracle.address, simpleOracle.address, uniswapLpOracle.address]
	)

	console.log('lp Px:', await uniswapLpOracle.getETHPx(lp));

	await oracle.setOracles(
		[usdc.address, usdt.address, lp],
		[
			[10000, 10000, 10000],
			[10000, 10000, 10000],
			[10000, 10000, 10000],
		]
	);
	await usdc.mint(alice.address, BigNumber.from(10).pow(6).mul(10_000_000))
	await usdt.mint(alice.address, BigNumber.from(10).pow(6).mul(10_000_000))
	await usdc.connect(alice).approve(bank.address, ethers.constants.MaxUint256);
	await usdt.connect(alice).approve(bank.address, ethers.constants.MaxUint256);

	return spell;
}

export const execute_uniswap_werc20 = async (
	admin: SignerWithAddress,
	alice: SignerWithAddress,
	bank: HomoraBank,
	token0: string,
	token1: string,
	spell: UniswapV2SpellV1,
	pos_id = 0
) => {
	await spell.getAndApprovePair(token0, token1);
	const lp = await spell.pairs(token0, token1);
	await spell.setWhitelistLPTokens([lp], [true]);
	await bank.connect(admin).setWhitelistSpells(
		[spell.address],
		[true]
	)

	const iface = new ethers.utils.Interface(SpellArtifact.abi);
	await bank.connect(alice).execute(
		pos_id,
		spell.address,
		iface.encodeFunctionData("addLiquidityWERC20", [
			token0,
			token1,
			[
				BigNumber.from(10).pow(6).mul(40_000),	// 40,000 USDT
				BigNumber.from(10).pow(6).mul(50_000),	// 50,000 USDC
				0,
				BigNumber.from(10).pow(6).mul(1_000),		// 1,000 USDT
				BigNumber.from(10).pow(6).mul(200),			// 200 USDC
				0,
				0,
				0,
			]
		])
	);
}