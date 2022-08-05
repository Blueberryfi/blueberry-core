import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { MockCErc20_2, MockWETH, SafeBoxETH } from '../typechain-types';
import { setupSafeBox } from './helpers/setup-safebox';

describe("SafeBoxEth", () => {
	let admin: SignerWithAddress;
	let alice: SignerWithAddress;
	let bob: SignerWithAddress;
	let eve: SignerWithAddress;
	let safeBoxEth: SafeBoxETH;
	let cweth: MockCErc20_2;
	let weth: MockWETH;

	before(async () => {
		[admin, alice, bob, eve] = await ethers.getSigners();
	})
	describe("Governor", () => {
		beforeEach(async function () {
			const fixture = await setupSafeBox();
			safeBoxEth = fixture.safeBoxEth;
		})
		it("should set deployer as default governor", async () => {
			expect(await safeBoxEth.governor()).to.be.equal(admin.address);
		})
		it("should set zero address as default pending governor", async () => {
			expect(await safeBoxEth.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);
		})
		it("should be able to set governor", async () => {
			expect(await safeBoxEth.governor()).to.be.equal(admin.address);
			expect(await safeBoxEth.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);

			// send pending governor to alice
			await safeBoxEth.setPendingGovernor(alice.address);
			expect(await safeBoxEth.governor()).to.be.equal(admin.address);
			expect(await safeBoxEth.pendingGovernor()).to.be.equal(alice.address);

			// accept governor
			await safeBoxEth.connect(alice).acceptGovernor();
			expect(await safeBoxEth.governor()).to.be.equal(alice.address);
			expect(await safeBoxEth.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);
		})

		it("should revert non-governor settings", async () => {
			expect(await safeBoxEth.governor()).to.be.equal(admin.address);
			expect(await safeBoxEth.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);

			// non-governor tries to set governor
			await expect(
				safeBoxEth.connect(alice).setPendingGovernor(bob.address)
			).to.be.revertedWith('not the governor');
			expect(await safeBoxEth.governor()).to.be.equal(admin.address);
			expect(await safeBoxEth.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);
			// admin sets self
			await expect(
				safeBoxEth.acceptGovernor()
			).to.be.revertedWith('not the pending governor');
			expect(await safeBoxEth.governor()).to.be.equal(admin.address);
			expect(await safeBoxEth.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);
			// governor sets another
			await safeBoxEth.setPendingGovernor(alice.address);
			expect(await safeBoxEth.governor()).to.be.equal(admin.address);
			expect(await safeBoxEth.pendingGovernor()).to.be.equal(alice.address);
			// alice tries to set without accepting
			await expect(
				safeBoxEth.connect(alice).setPendingGovernor(admin.address)
			).to.be.revertedWith('not the governor');
			// eve tries to accept
			await expect(
				safeBoxEth.connect(eve).acceptGovernor()
			).to.be.revertedWith('not the pending governor');
			expect(await safeBoxEth.governor()).to.be.equal(admin.address);
			expect(await safeBoxEth.pendingGovernor()).to.be.equal(alice.address);
			// alice accepts governor
			await safeBoxEth.connect(alice).acceptGovernor();
			expect(await safeBoxEth.governor()).to.be.equal(alice.address);
			expect(await safeBoxEth.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);
		})
		it("should be able to set governor twice", async () => {
			expect(await safeBoxEth.governor()).to.be.equal(admin.address);
			expect(await safeBoxEth.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);
			// mistakenly set eve to governor
			await safeBoxEth.setPendingGovernor(eve.address);
			expect(await safeBoxEth.governor()).to.be.equal(admin.address);
			expect(await safeBoxEth.pendingGovernor()).to.be.equal(eve.address);
			// set another governor before eve can accept
			await safeBoxEth.setPendingGovernor(alice.address);
			expect(await safeBoxEth.governor()).to.be.equal(admin.address);
			expect(await safeBoxEth.pendingGovernor()).to.be.equal(alice.address);
			// eve can no longer accept governor
			await expect(
				safeBoxEth.connect(eve).acceptGovernor()
			).to.be.revertedWith('not the pending governor');
			// alice accepts governor
			await safeBoxEth.connect(alice).acceptGovernor();
			expect(await safeBoxEth.governor()).to.be.equal(alice.address);
			expect(await safeBoxEth.pendingGovernor()).to.be.equal(ethers.constants.AddressZero);
		})
	})
	describe('Relayer', () => {
		beforeEach(async function () {
			const fixture = await setupSafeBox();
			safeBoxEth = fixture.safeBoxEth;
		})
		it("should set deployer as default relayer", async () => {
			expect(await safeBoxEth.relayer()).to.be.equal(admin.address);
		})
		it('should be able to set relayer', async () => {
			await safeBoxEth.setRelayer(alice.address);
			expect(await safeBoxEth.relayer()).to.be.equal(alice.address);
		})
		it("should allow relayer assignment only for governor", async () => {
			await expect(
				safeBoxEth.connect(eve).setRelayer(bob.address)
			).to.be.revertedWith('not the governor')
			expect(await safeBoxEth.relayer()).to.be.equal(admin.address);
			// governor sets relayer
			await safeBoxEth.setRelayer(alice.address);
			expect(await safeBoxEth.relayer()).to.be.equal(alice.address);
			// governor sets relayer
			await safeBoxEth.setRelayer(bob.address);
			expect(await safeBoxEth.relayer()).to.be.equal(bob.address);
		})
		it("should allow only governor and relayer to update root", async () => {
			await safeBoxEth.setRelayer(alice.address);
			expect(await safeBoxEth.root()).to.be.equal(ethers.constants.HashZero);
			// update from governor
			await safeBoxEth.updateRoot('0x0000000000000000000000000000000000000000000000000000000000000001');
			expect(await safeBoxEth.root()).to.be.equal('0x0000000000000000000000000000000000000000000000000000000000000001');
			// update from relayer
			await safeBoxEth.connect(alice).updateRoot('0x0000000000000000000000000000000000000000000000000000000000000002');
			expect(await safeBoxEth.root()).to.be.equal('0x0000000000000000000000000000000000000000000000000000000000000002');
			// update from non-authorized party
			await expect(
				safeBoxEth.connect(eve).updateRoot('0x0000000000000000000000000000000000000000000000000000000000000003')
			).to.be.revertedWith('!relayer');
		})
	})
	describe("Deposit and Claim", () => {
		beforeEach(async function () {
			const fixture = await setupSafeBox();
			safeBoxEth = fixture.safeBoxEth;
			cweth = fixture.cWeth;
			weth = fixture.mockWETH;
		})
		it("should be able to deposit and withdraw", async () => {
			const aliceDepositAmount = BigNumber.from(10).pow(18).mul(10);
			let prevAliceBalance = await alice.getBalance();
			await safeBoxEth.connect(alice).deposit({ value: aliceDepositAmount });
			expect(prevAliceBalance.sub(await alice.getBalance())).to.be.roughlyNear(aliceDepositAmount);
			expect(await cweth.balanceOf(safeBoxEth.address)).to.be.equal(aliceDepositAmount);

			const aliceWithdrawAmount = BigNumber.from(10).pow(18).mul(2);
			prevAliceBalance = await alice.getBalance();
			await safeBoxEth.connect(alice).withdraw(aliceWithdrawAmount);
			expect((await alice.getBalance()).sub(prevAliceBalance)).to.be.roughlyNear(aliceWithdrawAmount);
			expect(await cweth.balanceOf(safeBoxEth.address)).to.be.equal(aliceDepositAmount.sub(aliceWithdrawAmount));

			await cweth.setMintRate(BigNumber.from(10).pow(17).mul(11));
			expect(await cweth.mintRate()).to.be.equal(BigNumber.from(10).pow(17).mul(11));

			const aliceReWithdrawAmount = BigNumber.from(10).pow(18).mul(3);
			prevAliceBalance = await alice.getBalance();
			await safeBoxEth.connect(alice).withdraw(aliceReWithdrawAmount);
			expect((await alice.getBalance()).sub(prevAliceBalance)).to.be.roughlyNear(aliceReWithdrawAmount.mul(10).div(11))
			expect(await cweth.balanceOf(safeBoxEth.address)).to.be.equal(aliceDepositAmount.sub(aliceWithdrawAmount).sub(aliceReWithdrawAmount));
		})
		it("should allow adminClaim only for admin", async () => {
			const mintAmount = BigNumber.from(10).pow(18).mul(20);
			await weth.connect(alice).deposit({ value: mintAmount });
			await weth.connect(alice).transfer(safeBoxEth.address, mintAmount);

			const adminClaimAmount = BigNumber.from(10).pow(18).mul(7);
			const prevAdminBalance = await admin.getBalance();
			await safeBoxEth.adminClaim(adminClaimAmount);
			expect(await weth.balanceOf(safeBoxEth.address)).to.be.equal(mintAmount.sub(adminClaimAmount));
			expect((await admin.getBalance()).sub(prevAdminBalance)).to.be.roughlyNear(adminClaimAmount);

			await expect(
				safeBoxEth.connect(eve).adminClaim(adminClaimAmount)
			).to.be.revertedWith('not the governor')
		})
		it("should be able to claim", async () => {
			const mintAmount = BigNumber.from(10).pow(18).mul(1_000);
			await weth.deposit({ value: mintAmount });
			await weth.transfer(safeBoxEth.address, mintAmount);

			const user1 = '0x875B3a3374c63527271281a9254ad8926F021f1A';
			const user2 = '0xdAC17F958D2ee523a2206206994597C13D831ec7';
			// TODO: not implemented yet
		})
	})
})