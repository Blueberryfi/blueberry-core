import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai, { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import {
	BalancerPairOracle,
	CoreOracle,
	ERC20,
	IUniswapV2Pair,
	ProxyOracle,
	SimpleOracle,
	WERC20
} from '../../typechain-types';

import { solidity } from 'ethereum-waffle'
import { near } from '../assertions/near'
import { roughlyNear } from '../assertions/roughlyNear'
import { CONTRACT_NAMES } from '../../constants';

chai.use(solidity)
chai.use(near)
chai.use(roughlyNear)

const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
const BALANCER_LP = '0x8b6e6e7b5b3801fed2cafd4b22b8a16c2f2db21a';	// Balancer Pool Token - DAI/WETH
const UNI_LP = '0xa478c2975ab1ea89e8196811f51a7b7ade33eb11'				// Uniswap V2 Lp - DAI/WETH

describe('Bank Oracle', () => {
	let admin: SignerWithAddress;
	let alice: SignerWithAddress;

	let werc20: WERC20;
	let uniPair: IUniswapV2Pair;
	let simpleOracle: SimpleOracle;
	let balancerOracle: BalancerPairOracle;
	let coreOracle: CoreOracle;
	let oracle: ProxyOracle;

	before(async () => {
		[admin, alice] = await ethers.getSigners();

		const WERC20Factory = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
		werc20 = <WERC20>await WERC20Factory.deploy();
		await werc20.deployed();

		const SimpleOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.SimpleOracle);
		simpleOracle = <SimpleOracle>await SimpleOracleFactory.deploy();
		await simpleOracle.deployed();

		const BalancerPairOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.BalancerPairOracle);
		balancerOracle = <BalancerPairOracle>await BalancerPairOracleFactory.deploy(simpleOracle.address);
		await balancerOracle.deployed();

		const CoreOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
		coreOracle = <CoreOracle>await CoreOracleFactory.deploy();
		await coreOracle.deployed();

		const ProxyOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.ProxyOracle);
		oracle = <ProxyOracle>await ProxyOracleFactory.deploy(coreOracle.address);
		await oracle.deployed();

		uniPair = <IUniswapV2Pair>await ethers.getContractAt("IUniswapV2Pair", UNI_LP);
	})

	it("bank oracle price testing", async () => {
		const reserves = await uniPair.getReserves();
		const token0 = await uniPair.token0();
		let wethDaiPrice = ethers.constants.Zero;
		if (token0 === WETH) {
			wethDaiPrice = BigNumber.from(10).pow(18).mul(reserves.reserve1).div(reserves.reserve0);
		} else {
			wethDaiPrice = BigNumber.from(10).pow(18).mul(reserves.reserve0).div(reserves.reserve1);
		}

		await simpleOracle.setETHPx(
			[WETH, DAI],
			[
				BigNumber.from(2).pow(112),
				BigNumber.from(2).pow(112).mul(BigNumber.from(10).pow(18)).div(wethDaiPrice)
			]
		);

		await oracle.setWhitelistERC1155([werc20.address], true);
		await oracle.setTokenFactors(
			[WETH, DAI, BALANCER_LP],
			[
				{
					borrowFactor: 10000,
					collateralFactor: 10000,
					liqIncentive: 10000,
				}, {
					borrowFactor: 10000,
					collateralFactor: 10000,
					liqIncentive: 10000,
				}, {
					borrowFactor: 10000,
					collateralFactor: 10000,
					liqIncentive: 10000,
				},
			]
		);
		await coreOracle.setRoute(
			[WETH, DAI, BALANCER_LP],
			[simpleOracle.address, simpleOracle.address, balancerOracle.address]
		);

		//#####################################################################################
		const lpPrice = await balancerOracle.getETHPx(BALANCER_LP);
		const daiPrice = await simpleOracle.getETHPx(DAI);
		const wethPrice = await simpleOracle.getETHPx(WETH);

		const weth = <ERC20>await ethers.getContractAt(CONTRACT_NAMES.ERC20, WETH);
		const lpWethBalance = await weth.balanceOf(BALANCER_LP)

		const lp = <ERC20>await ethers.getContractAt(CONTRACT_NAMES.ERC20, BALANCER_LP);
		const lpSupply = await lp.totalSupply();

		expect(lpPrice).to.be.roughlyNear(
			lpWethBalance.mul(5).div(4).mul(BigNumber.from(2).pow(112)).div(lpSupply)
		)
	})
})