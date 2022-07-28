import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers, deployments, getNamedAccounts } from 'hardhat';
import { CONTRACT_NAMES } from "../constants"
import { CoreOracle, MockERC20, MockWETH, SimpleOracle } from '../typechain';
import { setupBasic } from './helpers/setup-basic';

const setupOracle = deployments.createFixture(async () => {
	const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
	const coreOracle = <CoreOracle>await CoreOracle.deploy();
	await coreOracle.deployed();

	return coreOracle;
})

describe('Core Oracle', () => {
	let admin: SignerWithAddress;
	let alice: SignerWithAddress;
	let bob: SignerWithAddress;
	let eve: SignerWithAddress;
	let coreOracle: CoreOracle;

	before(async () => {
		[admin, alice, bob, eve] = await ethers.getSigners();
	})
	describe('Governor', () => {
		beforeEach(async () => {
			const fixture = await setupBasic();
			coreOracle = fixture.coreOracle;
		})
		it("should set deployer as default owner", async () => {
			expect(await coreOracle.governor()).to.be.equal(admin.address);
		})
		it("should set zero address as default pending governer", async () => {
			expect(await coreOracle.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);
		})
		it("should be able to set governor", async () => {
			expect(await coreOracle.governor()).to.be.equal(admin.address);
			expect(await coreOracle.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);

			// set pending governor to alice
			await coreOracle.setPendingGovernor(alice.address);
			expect(await coreOracle.governor()).to.be.equal(admin.address);
			expect(await coreOracle.pendingGovernor()).to.be.equal(alice.address);

			// accept governor
			await coreOracle.connect(alice).acceptGovernor();
			expect(await coreOracle.governor()).to.be.equal(alice.address);
			expect(await coreOracle.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);
		})
		it("should revert governor setting", async () => {
			expect(await coreOracle.governor()).to.be.equal(admin.address);
			expect(await coreOracle.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);

			// revert setting governor from non-governor
			await expect(
				coreOracle.connect(alice).setPendingGovernor(bob.address)
			).to.be.revertedWith('not the governor');
			expect(await coreOracle.governor()).to.be.equal(admin.address);
			expect(await coreOracle.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);

			// admin sets self
			await coreOracle.setPendingGovernor(admin.address);
			expect(await coreOracle.governor()).to.be.equal(admin.address);
			expect(await coreOracle.pendingGovernor()).to.be.equal(admin.address);

			// accept self
			await coreOracle.acceptGovernor();
			expect(await coreOracle.governor()).to.be.equal(admin.address);
			expect(await coreOracle.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);

			// governor sets another
			await coreOracle.setPendingGovernor(alice.address);
			expect(await coreOracle.governor()).to.be.equal(admin.address);
			expect(await coreOracle.pendingGovernor()).to.be.equal(alice.address);

			// alice tries to set without accepting
			await expect(
				coreOracle.connect(alice).setPendingGovernor(admin.address)
			).to.be.revertedWith('not the governor');
			expect(await coreOracle.governor()).to.be.equal(admin.address);
			expect(await coreOracle.pendingGovernor()).to.be.equal(alice.address);

			// eve tries to accept
			await expect(
				coreOracle.connect(eve).acceptGovernor()
			).to.be.revertedWith('not the pending governor');
			expect(await coreOracle.governor()).to.be.equal(admin.address);
			expect(await coreOracle.pendingGovernor()).to.be.equal(alice.address);

			await coreOracle.connect(alice).acceptGovernor();
			expect(await coreOracle.governor()).to.be.equal(alice.address);
			expect(await coreOracle.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);
		})
		it("should be able to set governor twice", async () => {
			expect(await coreOracle.governor()).to.be.equal(admin.address);
			expect(await coreOracle.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);

			// mistakenly set eve to governor
			await coreOracle.setPendingGovernor(eve.address);
			expect(await coreOracle.governor()).to.be.equal(admin.address);
			expect(await coreOracle.pendingGovernor()).to.be.equal(eve.address);

			// set another governor before eve can accept
			await coreOracle.setPendingGovernor(alice.address);
			expect(await coreOracle.governor()).to.be.equal(admin.address);
			expect(await coreOracle.pendingGovernor()).to.be.equal(alice.address);

			// eve can no longer accept governor
			await expect(
				coreOracle.connect(eve).acceptGovernor()
			).to.be.revertedWith('not the pending governor');
			await coreOracle.connect(alice).acceptGovernor();
			expect(await coreOracle.governor()).to.be.equal(alice.address);
			expect(await coreOracle.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);
		})
	})
	describe("Route", () => {
		let weth: MockWETH;
		let usdc: MockERC20;
		let usdt: MockERC20;
		let dai: MockERC20;
		let simpleOracle: SimpleOracle;
		beforeEach(async () => {
			const fixture = await setupBasic();
			weth = fixture.mockWETH;
			usdt = fixture.usdt;
			usdc = fixture.usdc;
			dai = fixture.dai;
			simpleOracle = fixture.simpleOracle;
		})
		it("should be able to set route", async () => {
			expect(await coreOracle.routes(dai.address)).to.be.equal(ethers.constants.AddressZero);
			expect(await coreOracle.routes(usdt.address)).to.be.equal(ethers.constants.AddressZero);
			expect(await coreOracle.routes(usdc.address)).to.be.equal(ethers.constants.AddressZero);

			await simpleOracle.setETHPx([dai.address, usdc.address, usdt.address], [1, 2, 3]);

			// test multiple sources
			const SimpleOracle = await ethers.getContractFactory(CONTRACT_NAMES.SimpleOracle);
			const simpleOracle1 = <SimpleOracle>await SimpleOracle.deploy();
			await simpleOracle1.deployed();
			await simpleOracle1.setETHPx([dai.address, usdc.address, usdt.address], [4, 5, 6]);

			await coreOracle.setRoute(
				[dai.address, usdc.address, usdt.address],
				[simpleOracle.address, simpleOracle1.address, simpleOracle.address]
			);

			expect(await coreOracle.getETHPx(dai.address)).to.be.equal(1);
			expect(await coreOracle.getETHPx(usdc.address)).to.be.equal(5);
			expect(await coreOracle.getETHPx(usdt.address)).to.be.equal(3);

			await expect(coreOracle.getETHPx(weth.address)).to.be.reverted;

			// reset prices
			await simpleOracle.setETHPx([dai.address, usdc.address, usdt.address], [7, 8, 9]);
			await simpleOracle1.setETHPx([dai.address, usdc.address, usdt.address], [10, 11, 12]);

			expect(await coreOracle.getETHPx(dai.address)).to.be.equal(7);
			expect(await coreOracle.getETHPx(usdc.address)).to.be.equal(11);
			expect(await coreOracle.getETHPx(usdt.address)).to.be.equal(9);

			// re-route
			coreOracle.setRoute(
				[dai.address, usdc.address, usdt.address],
				[simpleOracle1.address, ethers.constants.AddressZero, simpleOracle1.address]
			)

			expect(await coreOracle.getETHPx(dai.address)).to.be.equal(10);
			expect(await coreOracle.getETHPx(usdt.address)).to.be.equal(12);

			await expect(coreOracle.getETHPx(usdc.address)).to.be.reverted;
		})
		it("should require same length", async () => {
			coreOracle.setRoute([], []);

			await expect(
				coreOracle.setRoute([dai.address], [])
			).to.be.revertedWith('inconsistent length');

			await expect(
				coreOracle.setRoute([], [ethers.constants.AddressZero, ethers.constants.AddressZero])
			).to.be.revertedWith('inconsistent length');

			await expect(
				coreOracle.setRoute(
					[dai.address, usdt.address],
					[ethers.constants.AddressZero]
				)
			).to.be.revertedWith('inconsistent length');
		})
	})
})