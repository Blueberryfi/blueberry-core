import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers, upgrades } from "hardhat";
import chai, { expect } from "chai";
import { ProtocolConfig } from "../typechain-types";
import { ADDRESS } from "../constant";
import { solidity } from 'ethereum-waffle'
import { BigNumber, utils } from "ethers";
import { roughlyNear } from "./assertions/roughlyNear";
import { near } from "./assertions/near";
import { evm_increaseTime } from "./helpers";
import exp from "constants";

chai.use(solidity);
chai.use(roughlyNear);
chai.use(near);

const USDC = ADDRESS.USDC;
const WETH = ADDRESS.WETH;

describe("HardVault", () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let bank: SignerWithAddress;
  let treasury: SignerWithAddress;

  let config: ProtocolConfig;

  before(async () => {
    [admin, alice, bank, treasury] = await ethers.getSigners();
  })

  beforeEach(async () => {
    const ProtocolConfig = await ethers.getContractFactory("ProtocolConfig");
    config = <ProtocolConfig>await upgrades.deployProxy(ProtocolConfig, [treasury.address]);
  })

  it("should revert when treasury address is invalid", async () => {
    const ProtocolConfig = await ethers.getContractFactory("ProtocolConfig");
    await expect(
      upgrades.deployProxy(ProtocolConfig, [ethers.constants.AddressZero])
    ).to.be.revertedWith("ZERO_ADDRESS");

    expect(await config.treasury()).to.be.equal(treasury.address)
  })
  it("should set initial states on constructor", async () => {
    expect(await config.depositFee()).to.be.equal(50);
    expect(await config.withdrawFee()).to.be.equal(50);
    expect(await config.treasuryFeeRate()).to.be.equal(3000);
    expect(await config.blbStablePoolFeeRate()).to.be.equal(3500);
    expect(await config.blbIchiVaultFeeRate()).to.be.equal(3500);
    expect(await config.withdrawVaultFee()).to.be.equal(100);
    expect(await config.withdrawVaultFeeWindow()).to.be.equal(60 * 60 * 24 * 60);
    expect(await config.withdrawVaultFeeWindowStartTime()).to.be.equal(0);
  })

  it("owner should be able to start vault withdraw fee", async () => {
    await expect(
      config.connect(alice).startVaultWithdrawFee()
    ).to.be.revertedWith("Ownable: caller is not the owner");

    await config.startVaultWithdrawFee();
  })

  it("owner should be able to set deposit fee", async () => {
    await expect(
      config.connect(alice).setDepositFee(100)
    ).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(
      config.setDepositFee(2500)
    ).to.be.revertedWith("FEE_TOO_HIGH");

    await config.setDepositFee(100);
    expect(await config.depositFee()).to.be.equal(100);
  })

  it("owner should be able to set withdraw fee", async () => {
    await expect(
      config.connect(alice).setWithdrawFee(100)
    ).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(
      config.setWithdrawFee(2500)
    ).to.be.revertedWith("FEE_TOO_HIGH");

    await config.setWithdrawFee(100);
    expect(await config.withdrawFee()).to.be.equal(100);
  })

  it("owner should be able to set fee distribution rates", async () => {
    await expect(
      config.connect(alice).setFeeDistribution(0, 0, 0)
    ).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(
      config.setFeeDistribution(0, 4000, 3000)
    ).to.be.revertedWith("INVALID_FEE_DISTRIBUTION");

    await config.setFeeDistribution(3000, 4000, 3000)
    expect(await config.treasuryFeeRate()).to.be.equal(3000);
    expect(await config.blbStablePoolFeeRate()).to.be.equal(4000);
    expect(await config.blbIchiVaultFeeRate()).to.be.equal(3000);
  })

  it("owner should be able to set treasury wallet", async () => {
    await expect(
      config.connect(alice).setTreasuryWallet(treasury.address)
    ).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(
      config.setTreasuryWallet(ethers.constants.AddressZero)
    ).to.be.revertedWith("ZERO_ADDRESS");

    await config.setTreasuryWallet(treasury.address);
    expect(await config.treasury()).to.be.equal(treasury.address);
  })

  it("owner should be able to set BLB/USDC ichi vault", async () => {
    await expect(
      config.connect(alice).setBlbUsdcIchiVault(treasury.address)
    ).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(
      config.setBlbUsdcIchiVault(ethers.constants.AddressZero)
    ).to.be.revertedWith("ZERO_ADDRESS");

    await config.setBlbUsdcIchiVault(treasury.address);
    expect(await config.blbUsdcIchiVault()).to.be.equal(treasury.address);
  })

  it("owner should be able to set BLB stable pool", async () => {
    await expect(
      config.connect(alice).setBlbStabilityPool(treasury.address)
    ).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(
      config.setBlbStabilityPool(ethers.constants.AddressZero)
    ).to.be.revertedWith("ZERO_ADDRESS");

    await config.setBlbStabilityPool(treasury.address);
    expect(await config.blbStabilityPool()).to.be.equal(treasury.address);
  })
})