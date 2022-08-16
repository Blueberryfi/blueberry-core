import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai, { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import {
	BalancerPairOracle,
	CoreOracle,
	ERC20,
	IUniswapV2Pair,
	ProxyOracle,
	SimpleOracle,
	WERC20
} from '../../typechain-types';

import { solidity } from 'ethereum-waffle'
import { near } from '../assertions/near'
import { roughlyNear } from '../assertions/roughlyNear'
import { ADDRESS, CONTRACT_NAMES } from '../../constants';

chai.use(solidity)
chai.use(near)
chai.use(roughlyNear)

const COMPTROLLER = ADDRESS.CREAM_COMP;	// Cream Finance / Comptroller
const ICETHER = ADDRESS.crETH;			// Cream Finance / crEth
const DAI = ADDRESS.DAI;
const WETH = ADDRESS.WETH;
const BALANCER_LP = ADDRESS.BAL_WETH_DAI_8020;

describe('Balancer Spell', () => {
	let admin: SignerWithAddress;
	let alice: SignerWithAddress;

	before(async () => {
		[admin, alice] = await ethers.getSigners();
	})
})