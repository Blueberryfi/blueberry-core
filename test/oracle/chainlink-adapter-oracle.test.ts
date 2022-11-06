import chai, { expect } from 'chai';
import { BigNumber, utils } from 'ethers';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import {
	ChainlinkAdapterOracle,
	IFeedRegistry,
} from '../../typechain-types';
import ChainlinkFeedABI from '../../abi/IFeedRegistry.json';

import { solidity } from 'ethereum-waffle'
import { near } from '../assertions/near'
import { roughlyNear } from '../assertions/roughlyNear'

chai.use(solidity)
chai.use(near)
chai.use(roughlyNear)

const OneDay = 86400;

describe('Chainlink Adapter Oracle', () => {
	let admin: SignerWithAddress;
	let alice: SignerWithAddress;
	let chainlinkAdapterOracle: ChainlinkAdapterOracle;
	let chainlinkFeedOracle: IFeedRegistry;
	before(async () => {
		[admin, alice] = await ethers.getSigners();
		chainlinkFeedOracle = <IFeedRegistry>await ethers.getContractAt(ChainlinkFeedABI, ADDRESS.ChainlinkRegistry);
	});

	beforeEach(async () => {
		const ChainlinkAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracle);
		chainlinkAdapterOracle = <ChainlinkAdapterOracle>await ChainlinkAdapterOracle.deploy(ADDRESS.ChainlinkRegistry);
		await chainlinkAdapterOracle.deployed();

		await chainlinkAdapterOracle.setMaxDelayTimes(
			[ADDRESS.USDC, ADDRESS.UNI],
			[OneDay, OneDay]
		);
	})

	describe("Constructor", () => {
		it("should revert when feed registry address is invalid", async () => {
			const ChainlinkAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracle);
			await expect(
				ChainlinkAdapterOracle.deploy(ethers.constants.AddressZero)
			).to.be.revertedWith('ZERO_ADDRESS');
		});
		it("should set feed registry", async () => {
			expect(await chainlinkAdapterOracle.registry()).to.be.equal(ADDRESS.ChainlinkRegistry);
		})
	})
	describe("Owner", () => {
		it("should be able to set feed registry", async () => {
			await expect(
				chainlinkAdapterOracle.connect(alice).setFeedRegistry(ADDRESS.ChainlinkRegistry)
			).to.be.revertedWith('Ownable: caller is not the owner');

			await expect(
				chainlinkAdapterOracle.setFeedRegistry(ethers.constants.AddressZero)
			).to.be.revertedWith('ZERO_ADDRESS');

			await expect(
				chainlinkAdapterOracle.setFeedRegistry(ADDRESS.ChainlinkRegistry)
			).to.be.emit(chainlinkAdapterOracle, "SetRegistry").withArgs(ADDRESS.ChainlinkRegistry);

			expect(await chainlinkAdapterOracle.registry()).to.be.equal(ADDRESS.ChainlinkRegistry);
		})
		it("should be able to set maxDelayTimes", async () => {
			await expect(chainlinkAdapterOracle.connect(alice).setMaxDelayTimes(
				[ADDRESS.USDC, ADDRESS.UNI],
				[OneDay, OneDay]
			)).to.be.revertedWith('Ownable: caller is not the owner');

			await expect(chainlinkAdapterOracle.setMaxDelayTimes(
				[ADDRESS.USDC, ADDRESS.UNI],
				[OneDay, OneDay, OneDay]
			)).to.be.revertedWith('INPUT_ARRAY_MISMATCH');

			await expect(chainlinkAdapterOracle.setMaxDelayTimes(
				[ADDRESS.USDC, ADDRESS.UNI],
				[OneDay, OneDay * 3]
			)).to.be.revertedWith('TOO_LONG_DELAY');

			await expect(chainlinkAdapterOracle.setMaxDelayTimes(
				[ADDRESS.USDC, ethers.constants.AddressZero],
				[OneDay, OneDay]
			)).to.be.revertedWith('ZERO_ADDRESS');

			await expect(chainlinkAdapterOracle.setMaxDelayTimes(
				[ADDRESS.USDC, ADDRESS.UNI],
				[OneDay, OneDay]
			)).to.be.emit(chainlinkAdapterOracle, 'SetMaxDelayTime');

			expect(await chainlinkAdapterOracle.maxDelayTimes(ADDRESS.USDC)).to.be.equal(OneDay);
		})
		it("should be able to set setTokenRemappings", async () => {
			await expect(chainlinkAdapterOracle.connect(alice).setTokenRemappings(
				[ADDRESS.USDC, ADDRESS.UNI],
				[ADDRESS.USDC, ADDRESS.UNI]
			)).to.be.revertedWith('Ownable: caller is not the owner');

			await expect(chainlinkAdapterOracle.setTokenRemappings(
				[ADDRESS.USDC, ADDRESS.UNI],
				[ADDRESS.USDC, ADDRESS.UNI, ADDRESS.UNI]
			)).to.be.revertedWith('INPUT_ARRAY_MISMATCH');

			await expect(chainlinkAdapterOracle.setTokenRemappings(
				[ADDRESS.USDC, ADDRESS.UNI],
				[ADDRESS.USDC, ethers.constants.AddressZero]
			)).to.be.revertedWith('ZERO_ADDRESS');

			await expect(chainlinkAdapterOracle.setTokenRemappings(
				[ADDRESS.USDC, ethers.constants.AddressZero],
				[ADDRESS.USDC, ADDRESS.UNI]
			)).to.be.revertedWith('ZERO_ADDRESS');

			await expect(chainlinkAdapterOracle.setTokenRemappings(
				[ADDRESS.USDC],
				[ADDRESS.USDC]
			)).to.be.emit(chainlinkAdapterOracle, 'SetTokenRemapping');

			expect(await chainlinkAdapterOracle.remappedTokens(ADDRESS.USDC)).to.be.equal(ADDRESS.USDC);
		})
	})

	describe('Price Feeds', () => {
		it("should revert when max delay time is not set", async () => {
			await expect(
				chainlinkAdapterOracle.getPrice(ADDRESS.CRV)
			).to.be.revertedWith('NO_MAX_DELAY');
		})
		it('USDC price feeds / based 10^18', async () => {
			const decimals = await chainlinkFeedOracle.decimals(ADDRESS.USDC, ADDRESS.CHAINLINK_USD);
			const { answer } = await chainlinkFeedOracle.latestRoundData(ADDRESS.USDC, ADDRESS.CHAINLINK_USD);
			const price = await chainlinkAdapterOracle.getPrice(ADDRESS.USDC);

			expect(
				answer.mul(BigNumber.from(10).pow(18)).div(BigNumber.from(10).pow(decimals))
			).to.be.roughlyNear(price);

			// real usdc price should be closed to $1
			expect(price).to.be.roughlyNear(BigNumber.from(10).pow(18));
			console.log('USDC Price:', utils.formatUnits(price, 18));
		})
		it('UNI price feeds / based 10^18', async () => {
			const decimals = await chainlinkFeedOracle.decimals(ADDRESS.UNI, ADDRESS.CHAINLINK_USD);
			const uniData = await chainlinkFeedOracle.latestRoundData(ADDRESS.UNI, ADDRESS.CHAINLINK_USD);
			const price = await chainlinkAdapterOracle.getPrice(ADDRESS.UNI);

			expect(
				uniData.answer.mul(BigNumber.from(10).pow(18)).div(BigNumber.from(10).pow(decimals))
			).to.be.roughlyNear(price);
			console.log('UNI Price:', utils.formatUnits(price, 18));
		})
		it('should revert for invalid feeds', async () => {
			await chainlinkAdapterOracle.setMaxDelayTimes([ADDRESS.ICHI], [OneDay]);
			await expect(
				chainlinkAdapterOracle.getPrice(ADDRESS.ICHI)
			).to.be.revertedWith('Feed not found');
		})
	})
});
