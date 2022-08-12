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
import { CONTRACT_NAMES } from '../../constants';

chai.use(solidity)
chai.use(near)
chai.use(roughlyNear)

const COMPTROLLER = '0x3d5BC3c8d13dcB8bF317092d84783c2697AE9258';	// Cream Finance / Comptroller
const ICETHER = '0xD06527D5e56A3495252A528C4987003b712860eE';			// Cream Finance / crEth
const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
const BALANCER_LP = '0x8b6e6e7b5b3801fed2cafd4b22b8a16c2f2db21a';

describe('Balancer Spell', () => {
	let admin: SignerWithAddress;
	let alice: SignerWithAddress;

	before(async () => {
		[admin, alice] = await ethers.getSigners();
	})
})