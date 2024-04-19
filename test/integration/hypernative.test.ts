import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai, { expect } from 'chai';
import { utils } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import { BlueberryBank, IchiSpell, ProtocolConfig, ERC20, MockIchiV2 } from '../../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import SpellABI from '../../abi/IchiSpell.json';

import { near } from '../assertions/near';
import { roughlyNear } from '../assertions/roughlyNear';
import { getSignatureFromData, Protocol, setupIchiProtocol } from '../helpers';
import { fork } from '../helpers';

chai.use(near);
chai.use(roughlyNear);

const USDC = ADDRESS.USDC;
const ICHI = ADDRESS.ICHI;
const ICHIV1 = ADDRESS.ICHI_FARM;
const ICHI_VAULT_PID = 0; // ICHI/USDC Vault PoolId

describe('Bank', () => {
  let admin: SignerWithAddress;
  let notSigner: SignerWithAddress;
  let treasury: SignerWithAddress;

  let usdc: ERC20;
  let ichi: MockIchiV2;
  let ichiV1: ERC20;
  let spell: IchiSpell;
  let bank: BlueberryBank;
  let config: ProtocolConfig;
  let protocol: Protocol;

  before(async () => {
    await fork();

    [admin, notSigner, treasury] = await ethers.getSigners();
    usdc = <ERC20>await ethers.getContractAt('ERC20', USDC);
    ichi = <MockIchiV2>await ethers.getContractAt('MockIchiV2', ICHI);
    ichiV1 = <ERC20>await ethers.getContractAt('ERC20', ICHIV1);

    const ProtocolConfig = await ethers.getContractFactory('ProtocolConfig');
    config = <ProtocolConfig>await upgrades.deployProxy(ProtocolConfig, [treasury.address, admin.address], {
      unsafeAllow: ['delegatecall'],
    });
    await config.deployed();
    await config.setSigner(admin.address);

    const BlueberryBank = await ethers.getContractFactory(CONTRACT_NAMES.BlueberryBank);
    bank = <BlueberryBank>await upgrades.deployProxy(
      BlueberryBank,
      [ethers.Wallet.createRandom().address, config.address, admin.address],
      {
        unsafeAllow: ['delegatecall'],
      }
    );
    await bank.deployed();

    protocol = await setupIchiProtocol();
    spell = protocol.ichiSpell;
  });

  describe('Execution', () => {
    const depositAmount = utils.parseUnits('10', 18); // worth of $400
    const borrowAmount = utils.parseUnits('30', 6);
    const iface = new ethers.utils.Interface(SpellABI);

    it('should revert when signer is invalid', async () => {
      const encodedData = iface.encodeFunctionData('openPosition', [
        {
          strategyId: 0,
          collToken: ICHI,
          borrowToken: USDC,
          collAmount: depositAmount,
          borrowAmount: borrowAmount,
          farmingPoolId: ICHI_VAULT_PID,
        },
      ]);
      const signature = await getSignatureFromData(notSigner, 0, spell.address, encodedData);
      await expect(bank.execute(0, spell.address, encodedData, signature)).to.be.revertedWith(
        'HypernativeProtector: Invalid signature'
      );
    });

    it('should not revert when signer is valid', async () => {
      const encodedData = iface.encodeFunctionData('openPosition', [
        {
          strategyId: 0,
          collToken: ICHI,
          borrowToken: USDC,
          collAmount: depositAmount,
          borrowAmount: borrowAmount,
          farmingPoolId: ICHI_VAULT_PID,
        },
      ]);
      const signature = await getSignatureFromData(admin, 0, spell.address, encodedData);
      await expect(bank.execute(0, spell.address, encodedData, signature)).to.not.be.revertedWith(
        'HypernativeProtector: Invalid signature'
      );
    });
  });
});
