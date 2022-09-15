import chai, { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ADDRESS, CONTRACT_NAMES } from '../../constants';
import {
	BandAdapterOracle,
	IStdReference,
} from '../../typechain-types';
import BandOracleABI from '../../abi/IStdReference.json';
import { roughlyNear } from '../assertions/roughlyNear';

chai.use(roughlyNear);

const OneDay = 86400;

describe('Base Oracle / Band Adapter Oracle', () => {
	let admin: SignerWithAddress;
	let user2: SignerWithAddress;
	let bandAdapterOracle: BandAdapterOracle;
	let bandBaseOracle: IStdReference;
	before(async () => {
		[admin, user2] = await ethers.getSigners();
		bandBaseOracle = <IStdReference>await ethers.getContractAt(BandOracleABI, ADDRESS.BandStdRef);
	});

	beforeEach(async () => {
		const BandAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.BandAdapterOracle);
		bandAdapterOracle = <BandAdapterOracle>await BandAdapterOracle.deploy(ADDRESS.BandStdRef);
		await bandAdapterOracle.deployed();

		await bandAdapterOracle.setMaxDelayTimes(
			[ADDRESS.USDC, ADDRESS.UNI],
			[OneDay, OneDay]
		);
		await bandAdapterOracle.setSymbols(
			[ADDRESS.USDC, ADDRESS.UNI],
			['USDC', 'UNI']
		);
	})

	it("should allow symbol settings only for owner", async () => {
		await expect(bandAdapterOracle.connect(user2).setSymbols(
			[ADDRESS.USDC, ADDRESS.UNI],
			['USDC', 'UNI']
		)).to.be.revertedWith('not the governor');

		await expect(bandAdapterOracle.setSymbols(
			[ADDRESS.USDC, ADDRESS.UNI],
			['USDC', 'UNI', 'DAI']
		)).to.be.revertedWith('length mismatch');

		await expect(bandAdapterOracle.setSymbols(
			[ADDRESS.USDC, ADDRESS.UNI],
			['USDC', 'UNI']
		)).to.be.emit(bandAdapterOracle, 'SetSymbol');

		expect(await bandAdapterOracle.symbols(ADDRESS.USDC)).to.be.equal('USDC');
	})

	it("should allow maxDelayTimes setting only for owner", async () => {
		await expect(bandAdapterOracle.connect(user2).setMaxDelayTimes(
			[ADDRESS.USDC, ADDRESS.UNI],
			[OneDay, OneDay]
		)).to.be.revertedWith('not the governor');

		await expect(bandAdapterOracle.setMaxDelayTimes(
			[ADDRESS.USDC, ADDRESS.UNI],
			[OneDay, OneDay, OneDay]
		)).to.be.revertedWith('length mismatch');

		await expect(bandAdapterOracle.setMaxDelayTimes(
			[ADDRESS.USDC, ADDRESS.UNI],
			[OneDay, OneDay]
		)).to.be.emit(bandAdapterOracle, 'SetMaxDelayTime');

		expect(await bandAdapterOracle.maxDelayTimes(ADDRESS.USDC)).to.be.equal(OneDay);
	})

	describe('price feeds', () => {
		it('USDC price feeds / based 2^112', async () => {
			const { rate } = await bandBaseOracle.getReferenceData('USDC', 'ETH');
			const ethData = await bandBaseOracle.getReferenceData('ETH', 'USD');
			const price = await bandAdapterOracle.getETHPx(ADDRESS.USDC);

			expect(
				price.mul(BigNumber.from(10).pow(18)).div(BigNumber.from(2).pow(112))
			).to.be.roughlyNear(rate);

			// real usdc price should be closed to $1
			expect(
				price.mul(ethData.rate).div(BigNumber.from(2).pow(112))
			).to.be.roughlyNear(BigNumber.from(10).pow(18));
		})
		it('UNI price feeds / based 2^112', async () => {
			const { rate } = await bandBaseOracle.getReferenceData('UNI', 'ETH');
			const ethData = await bandBaseOracle.getReferenceData('ETH', 'USD');
			const uniData = await bandBaseOracle.getReferenceData('UNI', 'USD');
			const price = await bandAdapterOracle.getETHPx(ADDRESS.UNI);

			expect(
				price.mul(BigNumber.from(10).pow(18)).div(BigNumber.from(2).pow(112))
			).to.be.roughlyNear(rate);

			expect(
				price.mul(ethData.rate).div(BigNumber.from(2).pow(112))
			).to.be.roughlyNear(uniData.rate);
		})
	})
});
