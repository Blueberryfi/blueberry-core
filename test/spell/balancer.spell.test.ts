import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai, { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import {
	BalancerPairOracle,
	CoreOracle,
	ERC20,
	IBalancerPool,
	ICErc20,
	IUniswapV2Pair,
	ProxyOracle,
	SimpleOracle,
	WERC20
} from '../../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../../constants';
import ERC20ABI from '../../abi/ERC20.json'
import BalancerPoolABI from '../../abi/IBalancerPool.json'
import ICrc20ABI from '../../abi/ICErc20.json'

import { solidity } from 'ethereum-waffle'
import { near } from '../assertions/near'
import { roughlyNear } from '../assertions/roughlyNear'

chai.use(solidity)
chai.use(near)
chai.use(roughlyNear)

const COMPTROLLER = ADDRESS.CREAM_COMP;	// Cream Finance / Comptroller
const CRDAI = ADDRESS.crDAI;			// Cream Finance / crDAI
const DAI = ADDRESS.DAI;
const WETH = ADDRESS.WETH;
const BALANCER_LP = ADDRESS.BAL_WETH_DAI_8020;

describe('Balancer Spell', () => {
	let admin: SignerWithAddress;
	let alice: SignerWithAddress;
	let dai: ERC20;
	let weth: ERC20;
	let balLp: ERC20;
	let balPool: IBalancerPool;
	let crDAI: ICErc20;
	let werc20: WERC20;
	let simpleOracle: SimpleOracle;
	let balancerOracle: BalancerPairOracle;
	let coreOracle: CoreOracle;
	let oracle: ProxyOracle;

	before(async () => {
		[admin, alice] = await ethers.getSigners();
		dai = <ERC20>await ethers.getContractAt(ERC20ABI, DAI, admin);
		weth = <ERC20>await ethers.getContractAt(ERC20ABI, WETH, admin);
		balLp = <ERC20>await ethers.getContractAt(ERC20ABI, BALANCER_LP);
		balPool = <IBalancerPool>await ethers.getContractAt(BalancerPoolABI, BALANCER_LP)
		crDAI = <ICErc20>await ethers.getContractAt(ICrc20ABI, CRDAI);

		const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
		werc20 = <WERC20>await WERC20.deploy();
		await werc20.deployed();

		const SimpleOracle = await ethers.getContractFactory(CONTRACT_NAMES.SimpleOracle);
		simpleOracle = <SimpleOracle>await SimpleOracle.deploy();
		await simpleOracle.deployed();
		await simpleOracle.setETHPx(
			[WETH, DAI],
			[5192296858534827628530496329220096, 8887571220661441971398610676149]
		)

		const BalancerOracle = await ethers.getContractFactory(CONTRACT_NAMES.BalancerPairOracle);
		balancerOracle = <BalancerPairOracle>await BalancerOracle.deploy(simpleOracle.address);
		await balancerOracle.deployed();

		const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
		coreOracle = <CoreOracle>await CoreOracle.deploy();
		await coreOracle.deployed();

		const ProxyOracle = await ethers.getContractFactory(CONTRACT_NAMES.ProxyOracle);
		oracle = <ProxyOracle>await ProxyOracle.deploy(coreOracle.address);
		await oracle.deployed();

		await oracle.setWhitelistERC1155([werc20.address], true);
		await coreOracle.setRoute(
			[WETH, DAI, BALANCER_LP],
			[simpleOracle.address, simpleOracle.address, balancerOracle.address]
		)
		await oracle.setTokenFactors(
			[WETH, DAI, BALANCER_LP],
			[{
				borrowFactor: 10000,
				collateralFactor: 10000,
				liqIncentive: 10000
			}, {
				borrowFactor: 10000,
				collateralFactor: 10000,
				liqIncentive: 10000
			}, {
				borrowFactor: 10000,
				collateralFactor: 10000,
				liqIncentive: 10000
			}]
		)


	})
})