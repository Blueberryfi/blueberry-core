import chai, { expect } from 'chai';
import { BigNumber, utils } from 'ethers';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import {
	AggregatorOracle,
	BandAdapterOracle,
	ChainlinkAdapterOracle,
	IFeedRegistry,
	IStdReference,
} from '../../typechain-types';
import ChainlinkFeedABI from '../../abi/IFeedRegistry.json';
import BandOracleABI from '../../abi/IStdReference.json';

import { solidity } from 'ethereum-waffle'
import { near } from '../assertions/near'
import { roughlyNear } from '../assertions/roughlyNear'

chai.use(solidity)
chai.use(near)
chai.use(roughlyNear)

const OneDay = 86400;
const DEVIATION = utils.parseEther("1.05");

describe('Aggregator Oracle', () => {
	let admin: SignerWithAddress;
	let alice: SignerWithAddress;

	let chainlinkFeedOracle: IFeedRegistry;
	let bandBaseOracle: IStdReference;

	let chainlinkOracle: ChainlinkAdapterOracle;
	let bandOracle: BandAdapterOracle;
	let aggregatorOracle: AggregatorOracle

	before(async () => {
		[admin, alice] = await ethers.getSigners();
		chainlinkFeedOracle = <IFeedRegistry>await ethers.getContractAt(ChainlinkFeedABI, ADDRESS.ChainlinkRegistry);
		bandBaseOracle = <IStdReference>await ethers.getContractAt(BandOracleABI, ADDRESS.BandStdRef);
	});

	beforeEach(async () => {
		// Chainlink Oracle
		const ChainlinkAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracle);
		chainlinkOracle = <ChainlinkAdapterOracle>await ChainlinkAdapterOracle.deploy(ADDRESS.ChainlinkRegistry);
		await chainlinkOracle.deployed();

		await chainlinkOracle.setMaxDelayTimes(
			[ADDRESS.USDC, ADDRESS.UNI, ADDRESS.CRV],
			[OneDay, OneDay, OneDay]
		);

		// Band Oracle
		const BandAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.BandAdapterOracle);
		bandOracle = <BandAdapterOracle>await BandAdapterOracle.deploy(ADDRESS.BandStdRef);
		await bandOracle.deployed();

		await bandOracle.setMaxDelayTimes(
			[ADDRESS.USDC, ADDRESS.UNI],
			[OneDay, OneDay]
		);
		await bandOracle.setSymbols(
			[ADDRESS.USDC, ADDRESS.UNI],
			['USDC', 'UNI']
		);

		const AggregatorOracle = await ethers.getContractFactory(CONTRACT_NAMES.AggregatorOracle);
		aggregatorOracle = <AggregatorOracle>await AggregatorOracle.deploy();
		await aggregatorOracle.deployed();
	})

	describe("Owner", () => {
		it("should be able to set primary sources", async () => {
			await expect(
				aggregatorOracle.connect(alice).setPrimarySources(
					ADDRESS.USDC,
					DEVIATION,
					[chainlinkOracle.address, bandOracle.address]
				)
			).to.be.revertedWith('Ownable: caller is not the owner');

			await expect(
				aggregatorOracle.setPrimarySources(
					ethers.constants.AddressZero,
					DEVIATION,
					[chainlinkOracle.address, bandOracle.address]
				)
			).to.be.revertedWith('ZERO_ADDRESS');

			await expect(
				aggregatorOracle.setPrimarySources(
					ADDRESS.UNI,
					DEVIATION.mul(2),
					[chainlinkOracle.address, bandOracle.address]
				)
			).to.be.revertedWith('OUT_OF_DEVIATION_CAP');

			await expect(
				aggregatorOracle.setPrimarySources(
					ADDRESS.UNI,
					0,
					[chainlinkOracle.address, bandOracle.address]
				)
			).to.be.revertedWith('OUT_OF_DEVIATION_CAP');

			await expect(
				aggregatorOracle.setPrimarySources(
					ADDRESS.UNI,
					DEVIATION,
					[chainlinkOracle.address, bandOracle.address, bandOracle.address, bandOracle.address]
				)
			).to.be.revertedWith('EXCEED_SOURCE_LEN(4)');

			await expect(
				aggregatorOracle.setPrimarySources(
					ADDRESS.UNI,
					DEVIATION,
					[chainlinkOracle.address, ethers.constants.AddressZero]
				)
			).to.be.revertedWith('ZERO_ADDRESS');

			await expect(
				aggregatorOracle.setPrimarySources(
					ADDRESS.UNI,
					DEVIATION,
					[chainlinkOracle.address, bandOracle.address]
				)
			).to.be.emit(aggregatorOracle, "SetPrimarySources");

			expect(await aggregatorOracle.maxPriceDeviations(ADDRESS.UNI)).to.be.equal(DEVIATION);
			expect(await aggregatorOracle.primarySourceCount(ADDRESS.UNI)).to.be.equal(2);
			expect(await aggregatorOracle.primarySources(ADDRESS.UNI, 0)).to.be.equal(chainlinkOracle.address);
			expect(await aggregatorOracle.primarySources(ADDRESS.UNI, 1)).to.be.equal(bandOracle.address);
		})
		it("should be able to set multiple primary sources", async () => {
			await expect(
				aggregatorOracle.connect(alice).setMultiPrimarySources(
					[ADDRESS.USDC, ADDRESS.UNI],
					[DEVIATION, DEVIATION],
					[
						[chainlinkOracle.address, bandOracle.address],
						[chainlinkOracle.address, bandOracle.address]
					]
				)
			).to.be.revertedWith('Ownable: caller is not the owner');

			await expect(
				aggregatorOracle.setMultiPrimarySources(
					[ADDRESS.USDC, ADDRESS.UNI],
					[DEVIATION],
					[
						[chainlinkOracle.address, bandOracle.address],
						[chainlinkOracle.address, bandOracle.address]
					]
				)
			).to.be.revertedWith('INPUT_ARRAY_MISMATCH');

			await expect(
				aggregatorOracle.setMultiPrimarySources(
					[ADDRESS.USDC, ADDRESS.UNI],
					[DEVIATION, DEVIATION],
					[
						[chainlinkOracle.address, bandOracle.address]
					]
				)
			).to.be.revertedWith('INPUT_ARRAY_MISMATCH');

			await expect(
				aggregatorOracle.setMultiPrimarySources(
					[ADDRESS.USDC, ADDRESS.UNI],
					[DEVIATION, DEVIATION],
					[
						[chainlinkOracle.address, bandOracle.address],
						[chainlinkOracle.address, bandOracle.address]
					]
				)
			).to.be.emit(aggregatorOracle, "SetPrimarySources");

			expect(await aggregatorOracle.maxPriceDeviations(ADDRESS.UNI)).to.be.equal(DEVIATION);
			expect(await aggregatorOracle.primarySourceCount(ADDRESS.UNI)).to.be.equal(2);
			expect(await aggregatorOracle.primarySources(ADDRESS.UNI, 0)).to.be.equal(chainlinkOracle.address);
			expect(await aggregatorOracle.primarySources(ADDRESS.UNI, 1)).to.be.equal(bandOracle.address);
		})
	})

	describe('Price Feeds', () => {
		beforeEach(async () => {
			await aggregatorOracle.setMultiPrimarySources(
				[ADDRESS.USDC, ADDRESS.UNI, ADDRESS.CRV, ADDRESS.ICHI],
				[DEVIATION, DEVIATION, DEVIATION, DEVIATION],
				[
					[chainlinkOracle.address, bandOracle.address],
					[chainlinkOracle.address, bandOracle.address, bandOracle.address],
					[chainlinkOracle.address],
					[chainlinkOracle.address, bandOracle.address],
				]
			)
		})
		it("should revert when there is no source", async () => {
			await expect(
				aggregatorOracle.getPrice(ADDRESS.COMP)
			).to.be.revertedWith(`NO_PRIMARY_SOURCE`);
		})
		it("should revert when there is no source returning valid price", async () => {
			await expect(
				aggregatorOracle.getPrice(ADDRESS.ICHI)
			).to.be.revertedWith(`NO_VALID_SOURCE`);
		})
		it("CRV price feeds", async () => {
			const token = ADDRESS.CRV;
			const chainlinkPrice = await chainlinkOracle.getPrice(token);
			console.log('CRV Price:', utils.formatUnits(chainlinkPrice, 18));

			const aggregatorPrice = await aggregatorOracle.getPrice(token);
			console.log(utils.formatUnits(aggregatorPrice, 18))
			expect(chainlinkPrice).to.be.equal(aggregatorPrice);
		})
		it("UNI price feeds", async () => {
			const token = ADDRESS.UNI;
			const chainlinkPrice = await chainlinkOracle.getPrice(token);
			const bandPrice = await bandOracle.getPrice(token);
			console.log('UNI Price:', utils.formatUnits(chainlinkPrice, 18), '/', utils.formatUnits(bandPrice, 18));

			const aggregatorPrice = await aggregatorOracle.getPrice(token);
			console.log(utils.formatUnits(aggregatorPrice, 18))
			expect(bandPrice).to.be.equal(aggregatorPrice);
		})
		it("USDC price feeds", async () => {
			const token = ADDRESS.USDC;
			const chainlinkPrice = await chainlinkOracle.getPrice(token);
			const bandPrice = await bandOracle.getPrice(token);
			console.log('USDC Price:', utils.formatUnits(chainlinkPrice, 18), '/', utils.formatUnits(bandPrice, 18));

			const aggregatorPrice = await aggregatorOracle.getPrice(token);
			console.log(utils.formatUnits(aggregatorPrice, 18))
			expect(chainlinkPrice.add(bandPrice).div(2)).to.be.equal(aggregatorPrice);
		})
	})
});
