import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers, deployments, getNamedAccounts } from 'hardhat';
import { CONTRACT_NAMES } from "../constants"
import { CoreOracle, MockERC20, MockWETH, SimpleOracle } from '../typechain';
import { setupBasic } from './helpers/setup-basic';
import { setupUniswap } from './helpers/setup-uniswap';

describe("Homora Bank", () => {
	let admin: SignerWithAddress;
	let alice: SignerWithAddress;
	let bob: SignerWithAddress;
	let eve: SignerWithAddress;

	before(async () => {
		[admin, alice, bob, eve] = await ethers.getSigners();
	})
	describe("Uniswap", () => {
		let fixture;
		beforeEach(async () => {
			fixture = await setupUniswap();
		})
	})
})