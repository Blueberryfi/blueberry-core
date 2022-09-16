import chai, { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from '../../constants';
import {
	SimpleOracle,
	CoreOracle,
	ProxyOracle,
	IchiLpOracle,
	IICHIVault,
	ChainlinkAdapterOracle,
	IERC20Ex,
} from '../../typechain-types';
import { roughlyNear } from '../assertions/roughlyNear';

chai.use(roughlyNear);

describe('Ichi Vault Lp Oracle', () => {
	let simpleOracle: SimpleOracle;
	let coreOracle: CoreOracle;
	let chainlinkAdapterOracle: ChainlinkAdapterOracle;
	let ichiOracle: IchiLpOracle;
	let ichiVault: IICHIVault;

	before(async () => {
		const SimpleOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.SimpleOracle);
		simpleOracle = <SimpleOracle>await SimpleOracleFactory.deploy();
		await simpleOracle.deployed();

		const CoreOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
		coreOracle = <CoreOracle>await CoreOracleFactory.deploy();
		await coreOracle.deployed();

		const ChainlinkAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracle);
		chainlinkAdapterOracle = <ChainlinkAdapterOracle>await ChainlinkAdapterOracle.deploy();
		await chainlinkAdapterOracle.deployed();
		await chainlinkAdapterOracle.setMaxDelayTimes([ADDRESS.USDC], [86400]);

		await coreOracle.setRoute(
			[ADDRESS.USDC, ADDRESS.ICHI],
			[
				chainlinkAdapterOracle.address,
				simpleOracle.address,
			]
		);

		ichiVault = <IICHIVault>await ethers.getContractAt(
			CONTRACT_NAMES.IICHIVault,
			ADDRESS.ICHI_VAULT_USDC
		);

	});

	it('USDC/ICHI Angel Vault Lp Price', async () => {
		const EthPrice = 1600;
		const ichiPrice = BigNumber.from(2).pow(112).mul(543).div(100).div(EthPrice); // $5.43

		await simpleOracle.setETHPx(
			[ADDRESS.ICHI], [ichiPrice]
		);

		const IchiLpOracle = await ethers.getContractFactory(CONTRACT_NAMES.IchiLpOracle);
		ichiOracle = <IchiLpOracle>(await IchiLpOracle.deploy(coreOracle.address));
		await ichiOracle.deployed();

		const lpPriceEth = await ichiOracle.getETHPx(ADDRESS.ICHI_VAULT_USDC);

		// calculate lp price manually.
		const reserveData = await ichiVault.getTotalAmounts();
		const token0 = await ichiVault.token0();
		const token1 = await ichiVault.token1();
		const totalSupply = await ichiVault.totalSupply();
		const usdcPrice = await chainlinkAdapterOracle.getETHPx(ADDRESS.USDC);
		const token0Contract = <IERC20Ex>await ethers.getContractAt(CONTRACT_NAMES.IERC20Ex, token0);
		const token1Contract = <IERC20Ex>await ethers.getContractAt(CONTRACT_NAMES.IERC20Ex, token1);
		const token0Decimal = await token0Contract.decimals();
		const token1Decimal = await token1Contract.decimals();

		const reserve1 = BigNumber.from(reserveData[0].mul(ichiPrice).div(BigNumber.from(10).pow(token0Decimal)));
		const reserve2 = BigNumber.from(reserveData[1].mul(usdcPrice).div(BigNumber.from(10).pow(token1Decimal)));
		const lpPriceM = reserve1.add(reserve2).mul(BigNumber.from(10).pow(18)).div(totalSupply).div(BigNumber.from(2).pow(112));
		const tvl = lpPriceM.mul(totalSupply).mul(EthPrice).div(BigNumber.from(10).pow(18));

		expect(
			lpPriceEth.mul(EthPrice).mul(totalSupply)
				.div(BigNumber.from(10).pow(18)).div(BigNumber.from(2).pow(112))
		).to.be.equal(tvl);
	});
});
