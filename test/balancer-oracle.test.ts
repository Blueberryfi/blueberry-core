import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai, { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { CONTRACT_NAMES } from "../constants"
import {
    BalancerPairOracle,
	CoreOracle,
	HomoraBank,
	SimpleOracle,
	WERC20,
	ProxyOracle,
    IUniswapV2Pair,
    IComptroller,
    ICEtherEx,
    ICurvePool,
} from '../typechain-types';
import { setupBasic } from './helpers/setup-basic';
import { solidity } from 'ethereum-waffle'
import { near } from './assertions/near'
import { roughlyNear } from './assertions/roughlyNear'

chai.use(solidity)
chai.use(near)
chai.use(roughlyNear)

describe('Balancer Oracle', () => {
    let admin: SignerWithAddress;
	let alice: SignerWithAddress;
	let bob: SignerWithAddress;
	let eve: SignerWithAddress;

    let bank: HomoraBank;
    let werc20: WERC20;
	let simpleOracle: SimpleOracle;
	let balancerOracle: BalancerPairOracle;
	let coreOracle: CoreOracle;
	let oracle: ProxyOracle;
    before(async () => {
        [admin, alice, bob, eve] = await ethers.getSigners();

        const WERC20Factory = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
		werc20 = <WERC20>await WERC20Factory.deploy();
		await werc20.deployed();

		const SimpleOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.SimpleOracle);
		simpleOracle = <SimpleOracle>await SimpleOracleFactory.deploy();
		await simpleOracle.deployed();

		const BalancerPairOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.BalancerPairOracle);
		balancerOracle = <BalancerPairOracle>await BalancerPairOracleFactory.deploy(simpleOracle.address);
		await balancerOracle.deployed();

		const CoreOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
		coreOracle = <CoreOracle>await CoreOracleFactory.deploy();
		await coreOracle.deployed();

		const ProxyOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.ProxyOracle);
		oracle = <ProxyOracle>await ProxyOracleFactory.deploy(coreOracle.address);
		await oracle.deployed();
    })

    describe('Basic', async () => {
        beforeEach(async ()=> {
            const basicFixture = await setupBasic();
            bank = basicFixture.homoraBank;
        })
        it('setup bank hack', async() => {
            const controllerAddr = "0x3d5BC3c8d13dcB8bF317092d84783c2697AE9258";
            const crethAddr= "0xD06527D5e56A3495252A528C4987003b712860eE";

            const controller = <IComptroller>await ethers.getContractAt(CONTRACT_NAMES.IComptroller, controllerAddr);
            const creth = <ICEtherEx>await ethers.getContractAt(CONTRACT_NAMES.ICEtherEx, crethAddr);

            // TODO: not implemented yet

            // await creth.mint({ 'value': ethers.utils.parseEther('100') });
            // await creth.connect(eve).transfer(bank.address, creth.balanceOf(eve));

            // await controller.connect(bank.address).enterMarkets([creth.address]);
        });
        it('bank oracle price testing', async() => {
            const wethAddr = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
            const daiAddr = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
            const lpAddr = "0x8b6e6e7b5b3801fed2cafd4b22b8a16c2f2db21a";
            const curveAddr = "0x8b6e6e7b5b3801fed2cafd4b22b8a16c2f2db21a";
            const uniAddr = "0xa478c2975ab1ea89e8196811f51a7b7ade33eb11";

            const weth = <ICEtherEx>await ethers.getContractAt(CONTRACT_NAMES.ICEtherEx, wethAddr);
            const dai = <ICEtherEx>await ethers.getContractAt(CONTRACT_NAMES.ICEtherEx, daiAddr);
            const lp = <ICEtherEx>await ethers.getContractAt(CONTRACT_NAMES.ICEtherEx, lpAddr);
            const curve = <ICurvePool>await ethers.getContractAt(CONTRACT_NAMES.ICurvePool, curveAddr);

            const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
            const werc20 = <WERC20>await WERC20.deploy();
            werc20.deployed();

            const uniPair = <IUniswapV2Pair>await ethers.getContractAt("IUniswapV2Pair", uniAddr);
            
            const reserves = await uniPair.getReserves();
            const token0 = await uniPair.token0();

            let wethDaiPrice = ethers.constants.Zero;
            if (token0 === wethAddr) {
                wethDaiPrice = BigNumber.from(10).pow(18).mul(reserves.reserve1).div(reserves.reserve0);
            } else {
                wethDaiPrice = BigNumber.from(10).pow(18).mul(reserves.reserve0).div(reserves.reserve1);
            }

            await simpleOracle.setETHPx(
                [wethAddr, daiAddr],
                [
                    BigNumber.from(2).pow(112),
                    BigNumber.from(2).pow(112).mul(BigNumber.from(10).pow(18)).div(wethDaiPrice)
                ]
            );

            await oracle.setWhitelistERC1155([werc20.address], true);
            await oracle.setTokenFactors(
                [wethAddr, daiAddr, lpAddr],
                [
                    {
                        borrowFactor: 10000,
                        collateralFactor: 10000,
                        liqIncentive: 10000,
                    }, {
                        borrowFactor: 10000,
                        collateralFactor: 10000,
                        liqIncentive: 10000,
                    }, {
                        borrowFactor: 10000,
                        collateralFactor: 10000,
                        liqIncentive: 10000,
                    },
                ]
            );

            await coreOracle.setRoute(
                [wethAddr, daiAddr, lpAddr],
                [simpleOracle.address, simpleOracle.address, balancerOracle.address]
            );

            const lpPrice = await balancerOracle.getETHPx(lpAddr);
            const daiPrice = await simpleOracle.getETHPx(daiAddr);
            const wethPrice = await simpleOracle.getETHPx(wethAddr);

            const lpWethBalance = await weth.balanceOf(lpAddr)

            const lpSupply = await lp.totalSupply();

            expect(lpPrice).to.be.roughlyNear(
                lpWethBalance.mul(5).div(4).mul(BigNumber.from(2).pow(112)).div(lpSupply)
            )
        })
    });
});