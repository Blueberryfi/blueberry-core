import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai, { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { CONTRACT_NAMES } from "../constants"
import {
    BalancerPairOracle,
	CoreOracle,
    CurveOracle,
	HomoraBank,
	SimpleOracle,
	WERC20,
	ProxyOracle,
    IUniswapV2Pair,
    IComptroller,
    ICEtherEx,
    ICErc20,
    ICurvePool,
    ICurveRegistry,
    IERC20Ex,
} from '../typechain-types';
import { solidity } from 'ethereum-waffle'
import { near } from './assertions/near'
import { roughlyNear } from './assertions/roughlyNear'

chai.use(solidity)
chai.use(near)
chai.use(roughlyNear)

describe('Curve Oracle', () => {
    let admin: SignerWithAddress;
	let alice: SignerWithAddress;
	let bob: SignerWithAddress;
	let eve: SignerWithAddress;

    let werc20: WERC20;
	let simpleOracle: SimpleOracle;
	let coreOracle: CoreOracle;
	let oracle: ProxyOracle;
    let curveOracle: CurveOracle;
    before(async () => {
        [admin, alice, bob, eve] = await ethers.getSigners();
        
        const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
        werc20 = <WERC20>await WERC20.deploy();
        await werc20.deployed();

		const SimpleOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.SimpleOracle);
		simpleOracle = <SimpleOracle>await SimpleOracleFactory.deploy();
		await simpleOracle.deployed();

		const CoreOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
		coreOracle = <CoreOracle>await CoreOracleFactory.deploy();
		await coreOracle.deployed();

		const ProxyOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.ProxyOracle);
		oracle = <ProxyOracle>await ProxyOracleFactory.deploy(coreOracle.address);
		await oracle.deployed();

    })

    describe('Basic', async () => {
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
            const daiAddr = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
            const usdcAddr = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
            const usdtAddr = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
            const lpAddr = "0x6c3f90f043a72fa612cbac8115ee7e52bde6e490";
            const curvepoolAddr = "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7";
            const curveregistryAddr = "0x7d86446ddb609ed0f5f8684acf30380a356b2b4c";
            const crdaiAddr = "0x92B767185fB3B04F881e3aC8e5B0662a027A1D9f";
            const crusdcAddr = "0x44fbebd2f576670a6c33f6fc0b00aa8c5753b322";
            const crusdtAddr = "0x797AAB1ce7c01eB727ab980762bA88e7133d2157";

            const dai = <IERC20Ex>await ethers.getContractAt(CONTRACT_NAMES.IERC20Ex, daiAddr);
            const usdc = <IERC20Ex>await ethers.getContractAt(CONTRACT_NAMES.IERC20Ex, usdcAddr);
            const usdt = <IERC20Ex>await ethers.getContractAt(CONTRACT_NAMES.IERC20Ex, usdtAddr);
            const lp = <IERC20Ex>await ethers.getContractAt(CONTRACT_NAMES.IERC20Ex, lpAddr);
            const curvepool = <ICurvePool>await ethers.getContractAt(CONTRACT_NAMES.ICurvePool, curvepoolAddr);
            const curveregistry = <ICurveRegistry>await ethers.getContractAt(CONTRACT_NAMES.ICurveRegistry, curveregistryAddr);
            const crdai = <ICErc20>await ethers.getContractAt(CONTRACT_NAMES.ICErc20, crdaiAddr);
            const crusdc = <ICErc20>await ethers.getContractAt(CONTRACT_NAMES.ICErc20, crusdcAddr);
            const crusdt = <ICErc20>await ethers.getContractAt(CONTRACT_NAMES.ICErc20, crusdtAddr);

            simpleOracle.setETHPx(
                [
                    daiAddr, 
                    usdtAddr, 
                    usdcAddr,
                    lpAddr
                ], 
                [
                    BigNumber.from(2).pow(112).div(600),
                    BigNumber.from(2).pow(112).mul(BigNumber.from(10).pow(12)).div(600),
                    BigNumber.from(2).pow(112).mul(BigNumber.from(10).pow(12)).div(600),
                    BigNumber.from(2).pow(112).div(600),
                ]
            )
            
            const CurveOracle = await ethers.getContractFactory(CONTRACT_NAMES.CurveOracle);
            curveOracle = <CurveOracle>await CurveOracle.deploy(simpleOracle.address, curveregistryAddr);
            await curveOracle.deployed();

            await curveOracle.registerPool(lpAddr);
            await oracle.setWhitelistERC1155([werc20.address], true);

            await coreOracle.setRoute(
                [
                    daiAddr, 
                    usdcAddr, 
                    usdtAddr, 
                    lpAddr
                ],
                [
                    simpleOracle.address, 
                    simpleOracle.address, 
                    simpleOracle.address, 
                    curveOracle.address
                ],
            );
            await oracle.setTokenFactors(
                [
                    daiAddr, 
                    usdcAddr, 
                    usdtAddr, 
                    lpAddr
                ],
                [
                    {
                        borrowFactor: 10000,
                        collateralFactor: 10000,
                        liqIncentive: 10000
                    }, {
                        borrowFactor: 10000,
                        collateralFactor: 10000,
                        liqIncentive: 10000
                    }, {
                        borrowFactor: 10000,
                        collateralFactor: 10000,
                        liqIncentive: 10000
                    }, {
                        borrowFactor: 10000,
                        collateralFactor: 10000,
                        liqIncentive: 10000
                    },
                ]
            );
            const lpPrice = await curveOracle.getETHPx(lpAddr)
            const daiPrice = await simpleOracle.getETHPx(daiAddr)
            const usdtPrice = await simpleOracle.getETHPx(usdtAddr)
            const usdcPrice = await simpleOracle.getETHPx(usdcAddr)

            const virtualPrice = await curvepool.get_virtual_price();

            expect(lpPrice).to.be.roughlyNear(
                virtualPrice.mul(BigNumber.from(10).pow(6)).mul(BigNumber.from(2).pow(112).div(600)).mul(BigNumber.from(10).pow(12)).div(BigNumber.from(10).pow(18)).div(BigNumber.from(10).pow(18))
            );
        })
    });
});