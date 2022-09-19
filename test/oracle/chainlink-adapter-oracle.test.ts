import chai, { expect } from 'chai';
import { BigNumber, utils } from 'ethers';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ADDRESS, CONTRACT_NAMES } from '../../constants';
import {
	ChainlinkAdapterOracle,
	IFeedRegistry,
} from '../../typechain-types';
import ChainlinkFeedABI from '../../abi/IFeedRegistry.json';
import { roughlyNear } from '../assertions/roughlyNear';

chai.use(roughlyNear);

const OneDay = 86400;

describe('Base Oracle / Chainlink Adapter Oracle', () => {
	let admin: SignerWithAddress;
	let user2: SignerWithAddress;
	let chainlinkAdapterOracle: ChainlinkAdapterOracle;
	let chainlinkFeedOracle: IFeedRegistry;
	before(async () => {
		[admin, user2] = await ethers.getSigners();
		chainlinkFeedOracle = <IFeedRegistry>await ethers.getContractAt(ChainlinkFeedABI, ADDRESS.ChainlinkRegistry);
	});

	beforeEach(async () => {
		const ChainlinkAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracle);
		chainlinkAdapterOracle = <ChainlinkAdapterOracle>await ChainlinkAdapterOracle.deploy();
		await chainlinkAdapterOracle.deployed();

		await chainlinkAdapterOracle.setMaxDelayTimes(
			[ADDRESS.USDC, ADDRESS.UNI],
			[OneDay, OneDay]
		);
	})

	it("should allow maxDelayTimes setting only for owner", async () => {
		await expect(chainlinkAdapterOracle.connect(user2).setMaxDelayTimes(
			[ADDRESS.USDC, ADDRESS.UNI],
			[OneDay, OneDay]
		)).to.be.revertedWith('Ownable: caller is not the owner');

		await expect(chainlinkAdapterOracle.setMaxDelayTimes(
			[ADDRESS.USDC, ADDRESS.UNI],
			[OneDay, OneDay, OneDay]
		)).to.be.revertedWith('length mismatch');

		await expect(chainlinkAdapterOracle.setMaxDelayTimes(
			[ADDRESS.USDC, ADDRESS.UNI],
			[OneDay, OneDay]
		)).to.be.emit(chainlinkAdapterOracle, 'SetMaxDelayTime');

		expect(await chainlinkAdapterOracle.maxDelayTimes(ADDRESS.USDC)).to.be.equal(OneDay);
	})

	describe('price feeds', () => {
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
