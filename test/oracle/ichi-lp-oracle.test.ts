import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai, { expect } from 'chai';
import { BigNumber, utils } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import {
	MockOracle,
	CoreOracle,
	IchiLpOracle,
	IICHIVault,
	ChainlinkAdapterOracle,
	IERC20Metadata,
} from '../../typechain-types';
import { roughlyNear } from '../assertions/roughlyNear';

chai.use(roughlyNear);

describe('Ichi Vault Lp Oracle', () => {
	let admin: SignerWithAddress;
	let mockOracle: MockOracle;
	let coreOracle: CoreOracle;
	let chainlinkAdapterOracle: ChainlinkAdapterOracle;
	let ichiOracle: IchiLpOracle;
	let ichiVault: IICHIVault;

	before(async () => {
		[admin] = await ethers.getSigners();

		const MockOracle = await ethers.getContractFactory(CONTRACT_NAMES.MockOracle);
		mockOracle = <MockOracle>await MockOracle.deploy();
		await mockOracle.deployed();

		const CoreOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
		coreOracle = <CoreOracle>await upgrades.deployProxy(CoreOracleFactory);
		await coreOracle.deployed();

		const ChainlinkAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracle);
		chainlinkAdapterOracle = <ChainlinkAdapterOracle>await ChainlinkAdapterOracle.deploy(ADDRESS.ChainlinkRegistry);
		await chainlinkAdapterOracle.deployed();
		await chainlinkAdapterOracle.setMaxDelayTimes([ADDRESS.USDC], [86400]);

		await coreOracle.setRoute(
			[ADDRESS.USDC, ADDRESS.ICHI],
			[
				chainlinkAdapterOracle.address,
				mockOracle.address,
			]
		);

		ichiVault = <IICHIVault>await ethers.getContractAt(
			CONTRACT_NAMES.IICHIVault,
			ADDRESS.ICHI_VAULT_USDC
		);

	});

	it('USDC/ICHI Angel Vault Lp Price', async () => {
		const ichiPrice = BigNumber.from(10).pow(18).mul(543).div(100); // $5.43

		await mockOracle.setPrice(
			[ADDRESS.ICHI], [ichiPrice]
		);

		const IchiLpOracle = await ethers.getContractFactory(CONTRACT_NAMES.IchiLpOracle);
		ichiOracle = <IchiLpOracle>(await IchiLpOracle.deploy(coreOracle.address));
		await ichiOracle.deployed();

		const lpPrice = await ichiOracle.getPrice(ADDRESS.ICHI_VAULT_USDC);

		// calculate lp price manually.
		const reserveData = await ichiVault.getTotalAmounts();
		const token0 = await ichiVault.token0();
		const token1 = await ichiVault.token1();
		const totalSupply = await ichiVault.totalSupply();
		const usdcPrice = await chainlinkAdapterOracle.getPrice(ADDRESS.USDC);
		const token0Contract = <IERC20Metadata>await ethers.getContractAt(CONTRACT_NAMES.IERC20Metadata, token0);
		const token1Contract = <IERC20Metadata>await ethers.getContractAt(CONTRACT_NAMES.IERC20Metadata, token1);
		const token0Decimal = await token0Contract.decimals();
		const token1Decimal = await token1Contract.decimals();

		const reserve1 = BigNumber.from(reserveData[0].mul(ichiPrice).div(BigNumber.from(10).pow(token0Decimal)));
		const reserve2 = BigNumber.from(reserveData[1].mul(usdcPrice).div(BigNumber.from(10).pow(token1Decimal)));
		const lpPriceM = reserve1.add(reserve2).mul(BigNumber.from(10).pow(18)).div(totalSupply);
		const tvl = lpPriceM.mul(totalSupply).div(BigNumber.from(10).pow(18));

		expect(
			lpPrice.mul(totalSupply).div(BigNumber.from(10).pow(18))
		).to.be.equal(tvl);
		console.log('USDC/ICHI Lp Price:', utils.formatUnits(lpPrice, 18));
		console.log('TVL:', utils.formatUnits(tvl, 18));
	});

	it("USDC/ICHI empty pool price", async () => {
		const LinkedLibFactory = await ethers.getContractFactory("UniV3WrappedLib");
		const LibInstance = await LinkedLibFactory.deploy();

		const IchiVault = await ethers.getContractFactory("MockIchiVault", {
			libraries: {
				UniV3WrappedLibMockup: LibInstance.address
			}
		});
		const newVault = await IchiVault.deploy(
			ADDRESS.UNI_V3_ICHI_USDC,
			true,
			true,
			admin.address,
			admin.address,
			3600
		)

		const price = await ichiOracle.getPrice(newVault.address);
		expect(price).to.be.equal(0);
	})
});
