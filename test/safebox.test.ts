import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers, waffle } from 'hardhat';
import { MockCErc202, MockERC20, MockWETH, SafeBox } from '../typechain';
import { setupSafeBox } from './helpers/setup-safebox';

describe("SafeBox", () => {
	let admin: SignerWithAddress;
	let alice: SignerWithAddress;
	let bob: SignerWithAddress;
	let eve: SignerWithAddress;
	let safeBox: SafeBox;
	let cweth: MockCErc202;
	let weth: MockWETH;
	let token: MockERC20;
	let ctoken: MockCErc202;

	before(async () => {
		[admin, alice, bob, eve] = await ethers.getSigners();
	})
	describe("Governor", () => {
		beforeEach(async function () {
			const fixture = await setupSafeBox();
			safeBox = fixture.safeBox;
		})
		it("should set deployer as default governor", async () => {
			expect(await safeBox.governor()).to.be.equal(admin.address);
		})
		it("should set zero address as default pending governor", async () => {
			expect(await safeBox.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);
		})
		it("should be able to set governor", async () => {
			expect(await safeBox.governor()).to.be.equal(admin.address);
			expect(await safeBox.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);

			// send pending governor to alice
			await safeBox.setPendingGovernor(alice.address);
			expect(await safeBox.governor()).to.be.equal(admin.address);
			expect(await safeBox.pendingGovernor()).to.be.equal(alice.address);

			// accept governor
			await safeBox.connect(alice).acceptGovernor();
			expect(await safeBox.governor()).to.be.equal(alice.address);
			expect(await safeBox.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);
		})

		it("should revert non-governor settings", async () => {
			expect(await safeBox.governor()).to.be.equal(admin.address);
			expect(await safeBox.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);

			// non-governor tries to set governor
			await expect(
				safeBox.connect(alice).setPendingGovernor(bob.address)
			).to.be.revertedWith('not the governor');
			expect(await safeBox.governor()).to.be.equal(admin.address);
			expect(await safeBox.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);
			// admin sets self
			await expect(
				safeBox.acceptGovernor()
			).to.be.revertedWith('not the pending governor');
			expect(await safeBox.governor()).to.be.equal(admin.address);
			expect(await safeBox.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);
			// governor sets another
			await safeBox.setPendingGovernor(alice.address);
			expect(await safeBox.governor()).to.be.equal(admin.address);
			expect(await safeBox.pendingGovernor()).to.be.equal(alice.address);
			// alice tries to set without accepting
			await expect(
				safeBox.connect(alice).setPendingGovernor(admin.address)
			).to.be.revertedWith('not the governor');
			// eve tries to accept
			await expect(
				safeBox.connect(eve).acceptGovernor()
			).to.be.revertedWith('not the pending governor');
			expect(await safeBox.governor()).to.be.equal(admin.address);
			expect(await safeBox.pendingGovernor()).to.be.equal(alice.address);
			// alice accepts governor
			await safeBox.connect(alice).acceptGovernor();
			expect(await safeBox.governor()).to.be.equal(alice.address);
			expect(await safeBox.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);
		})
		it("should be able to set governor twice", async () => {
			expect(await safeBox.governor()).to.be.equal(admin.address);
			expect(await safeBox.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);
			// mistakenly set eve to governor
			await safeBox.setPendingGovernor(eve.address);
			expect(await safeBox.governor()).to.be.equal(admin.address);
			expect(await safeBox.pendingGovernor()).to.be.equal(eve.address);
			// set another governor before eve can accept
			await safeBox.setPendingGovernor(alice.address);
			expect(await safeBox.governor()).to.be.equal(admin.address);
			expect(await safeBox.pendingGovernor()).to.be.equal(alice.address);
			// eve can no longer accept governor
			await expect(
				safeBox.connect(eve).acceptGovernor()
			).to.be.revertedWith('not the pending governor');
			// alice accepts governor
			await safeBox.connect(alice).acceptGovernor();
			expect(await safeBox.governor()).to.be.equal(alice.address);
			expect(await safeBox.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);
		})
	})
	describe('Relayer', () => {
		beforeEach(async function () {
			const fixture = await setupSafeBox();
			safeBox = fixture.safeBox;
		})
		it("should set deployer as default relayer", async () => {
			expect(await safeBox.relayer()).to.be.equal(admin.address);
		})
		it('should be able to set relayer', async () => {
			await safeBox.setRelayer(alice.address);
			expect(await safeBox.relayer()).to.be.equal(alice.address);
		})
		it("should allow relayer assignment only for governor", async () => {
			await expect(
				safeBox.connect(eve).setRelayer(bob.address)
			).to.be.revertedWith('not the governor')
			expect(await safeBox.relayer()).to.be.equal(admin.address);
			// governor sets relayer
			await safeBox.setRelayer(alice.address);
			expect(await safeBox.relayer()).to.be.equal(alice.address);
			// governor sets relayer
			await safeBox.setRelayer(bob.address);
			expect(await safeBox.relayer()).to.be.equal(bob.address);
		})
		it("should allow only governor and relayer to update root", async () => {
			await safeBox.setRelayer(alice.address);
			expect(await safeBox.root()).to.be.equal(ethers.constants.HashZero);
			// update from governor
			await safeBox.updateRoot('0x0000000000000000000000000000000000000000000000000000000000000001');
			expect(await safeBox.root()).to.be.equal('0x0000000000000000000000000000000000000000000000000000000000000001');
			// update from relayer
			await safeBox.connect(alice).updateRoot('0x0000000000000000000000000000000000000000000000000000000000000002');
			expect(await safeBox.root()).to.be.equal('0x0000000000000000000000000000000000000000000000000000000000000002');
			// update from non-authorized party
			await expect(
				safeBox.connect(eve).updateRoot('0x0000000000000000000000000000000000000000000000000000000000000003')
			).to.be.revertedWith('!relayer');
		})
	})
	describe("Deposit and Claim", () => {
		beforeEach(async function () {
			const fixture = await setupSafeBox();
			safeBox = fixture.safeBox;
			cweth = fixture.cWeth;
			weth = fixture.mockWETH;
			token = fixture.mockERC20;
			ctoken = fixture.cToken;
		})
		it("should be able to deposit and withdraw", async () => {
			const aliceMintAmount = BigNumber.from(10).pow(18).mul(1000);
			await token.mint(alice.address, aliceMintAmount);
			await token.connect(alice).approve(safeBox.address, ethers.constants.MaxUint256);

			const aliceDepositAmount = BigNumber.from(10).pow(18).mul(10);
			await safeBox.connect(alice).deposit(aliceDepositAmount);
			expect(await token.balanceOf(alice.address)).to.be.equal(aliceMintAmount.sub(aliceDepositAmount));
			expect(await ctoken.balanceOf(safeBox.address)).to.be.equal(aliceDepositAmount);

			const aliceWithdrawAmount = BigNumber.from(10).pow(18).mul(2);
			await safeBox.connect(alice).withdraw(aliceWithdrawAmount);
			expect(await token.balanceOf(alice.address)).to.be.equal(
				aliceMintAmount.sub(aliceDepositAmount).add(aliceWithdrawAmount)
			);
			expect(await ctoken.balanceOf(safeBox.address)).to.be.equal(aliceDepositAmount.sub(aliceWithdrawAmount));

			await ctoken.setMintRate(BigNumber.from(10).pow(17).mul(11));
			expect(await ctoken.mintRate()).to.be.equal(BigNumber.from(10).pow(17).mul(11));

			const aliceReWithdrawAmount = BigNumber.from(10).pow(18).mul(3);
			await safeBox.connect(alice).withdraw(aliceReWithdrawAmount);
			expect(await token.balanceOf(alice.address)).to.be.equal(
				aliceMintAmount.sub(aliceDepositAmount).add(aliceWithdrawAmount).add(
					aliceReWithdrawAmount.mul(10).div(11)
				)
			)
			expect(await ctoken.balanceOf(safeBox.address)).to.be.equal(
				aliceDepositAmount.sub(aliceWithdrawAmount).sub(aliceReWithdrawAmount)
			);
		})
		it("should allow adminClaim only for admin", async () => {
			const mintAmount = BigNumber.from(10).pow(18).mul(100);
			await token.mint(safeBox.address, mintAmount);

			const adminClaimAmount = BigNumber.from(10).pow(18).mul(5);
			await safeBox.adminClaim(adminClaimAmount);
			expect(await token.balanceOf(safeBox.address)).to.be.equal(mintAmount.sub(adminClaimAmount));
			expect(await token.balanceOf(admin.address)).to.be.equal(adminClaimAmount);

			await expect(
				safeBox.connect(eve).adminClaim(adminClaimAmount)
			).to.be.revertedWith('not the governor')
		})
		it("should be able to claim", async () => {
			const mintAmount = BigNumber.from(10).pow(18).mul(1_000);
			await token.mint(safeBox.address, mintAmount);

			await safeBox.updateRoot('0xaee410ac1087d10cadac9200aea45b43b7f48a5c75ba30988eeddf29db4303ad');
			// await safeBox.connect(alice).claim(9231, [
			// 	'0x69f3f45eba22069136bcf167cf8d409b0fc92841af8112ad94696c72c4fd281d',
			// 	'0xd841f03d02a38c6b5c9f2042bc8877162e45b1d9de0fdd5711fa735827760f9b',
			// 	'0xd279da13820e67ddd2615d2412ffef5470abeb32ba6a387005036fdd0b5ff889'
			// ]);
			// TODO: not implemented yet
		})
	})
})