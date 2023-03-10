import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import chai, {expect, util} from "chai";
import {BigNumber, utils} from "ethers";
import {ethers, upgrades} from "hardhat";
import {ADDRESS, CONTRACT_NAMES} from "../../constant";
import {
    ISwapRouter,
    MockOracle,
    CoreOracle,
    IchiVaultOracle,
    IICHIVault,
    ChainlinkAdapterOracle,
    IERC20Metadata,
    UniswapV3AdapterOracle,
    IWETH,
    IUniswapV2Router02,
    ERC20,
    MockIchiV2,
} from "../../typechain-types";
import {roughlyNear} from "../assertions/roughlyNear";
import {solidity} from "ethereum-waffle";

chai.use(roughlyNear);
chai.use(solidity);

const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const ICHI = ADDRESS.ICHI;
const ICHIV1 = ADDRESS.ICHI_FARM;
const SWAP_ROUTER = ADDRESS.UNI_V3_ROUTER;

describe("Ichi Vault Oracle", () => {
    let admin: SignerWithAddress;
    let mockOracle: MockOracle;
    let coreOracle: CoreOracle;
    let chainlinkAdapterOracle: ChainlinkAdapterOracle;
    let ichiOracle: IchiVaultOracle;
    let ichiVault: IICHIVault;
    let uniswapV3Oracle: UniswapV3AdapterOracle;
    let swapRouter: ISwapRouter;

    let weth: IWETH;
    let usdc: ERC20;
    let ichi: MockIchiV2;
    let ichiV1: ERC20;

    before(async () => {
        [admin] = await ethers.getSigners();

        usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
        ichi = <MockIchiV2>await ethers.getContractAt("MockIchiV2", ICHI);
        ichiV1 = <ERC20>await ethers.getContractAt("ERC20", ICHIV1);
        weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);
        swapRouter = <ISwapRouter>(
            await ethers.getContractAt(
                CONTRACT_NAMES.IUniSwapRouter,
                SWAP_ROUTER
            )
        );

        const MockOracle = await ethers.getContractFactory(
            CONTRACT_NAMES.MockOracle
        );
        mockOracle = <MockOracle>await MockOracle.deploy();
        await mockOracle.deployed();

        const CoreOracleFactory = await ethers.getContractFactory(
            CONTRACT_NAMES.CoreOracle
        );
        coreOracle = <CoreOracle>await upgrades.deployProxy(CoreOracleFactory);
        await coreOracle.deployed();

        const ChainlinkAdapterOracle = await ethers.getContractFactory(
            CONTRACT_NAMES.ChainlinkAdapterOracle
        );
        chainlinkAdapterOracle = <ChainlinkAdapterOracle>(
            await ChainlinkAdapterOracle.deploy(ADDRESS.ChainlinkRegistry)
        );
        await chainlinkAdapterOracle.deployed();
        await chainlinkAdapterOracle.setMaxDelayTimes([ADDRESS.USDC], [86400]);

        ichiVault = <IICHIVault>(
            await ethers.getContractAt(
                CONTRACT_NAMES.IICHIVault,
                ADDRESS.ICHI_VAULT_USDC
            )
        );

        const LinkedLibFactory = await ethers.getContractFactory(
            "UniV3WrappedLib"
        );
        const LibInstance = await LinkedLibFactory.deploy();
        const UniswapV3AdapterOracle = await ethers.getContractFactory(
            CONTRACT_NAMES.UniswapV3AdapterOracle,
            {
                libraries: {
                    UniV3WrappedLibMockup: LibInstance.address,
                },
            }
        );
        uniswapV3Oracle = <UniswapV3AdapterOracle>(
            await UniswapV3AdapterOracle.deploy(coreOracle.address)
        );
        await uniswapV3Oracle.deployed();
        await uniswapV3Oracle.setStablePools(
            [ADDRESS.ICHI],
            [ADDRESS.UNI_V3_ICHI_USDC]
        );
        await uniswapV3Oracle.setMaxDelayTimes(
            [ADDRESS.ICHI],
            [10] // timeAgo - 10 s
        );

        await coreOracle.setRoutes(
            [ADDRESS.USDC, ADDRESS.ICHI],
            [chainlinkAdapterOracle.address, uniswapV3Oracle.address]
        );

        const IchiVaultOracle = await ethers.getContractFactory(
            CONTRACT_NAMES.IchiVaultOracle
        );
        ichiOracle = <IchiVaultOracle>(
            await IchiVaultOracle.deploy(coreOracle.address)
        );
        await ichiOracle.deployed();
    });

    it("USDC/ICHI Angel Vault Lp Price", async () => {
        const ichiPrice = await uniswapV3Oracle.getPrice(ADDRESS.ICHI);
        console.log("ICHI Price", utils.formatUnits(ichiPrice));

        const lpPrice = await ichiOracle.getPrice(ADDRESS.ICHI_VAULT_USDC);
        console.log("USDC/ICHI Lp Price: \t", utils.formatUnits(lpPrice, 18));

        // calculate lp price manually.
        const reserveData = await ichiVault.getTotalAmounts();
        const token0 = await ichiVault.token0();
        const token1 = await ichiVault.token1();
        const totalSupply = await ichiVault.totalSupply();
        const usdcPrice = await coreOracle.getPrice(ADDRESS.USDC);
        const token0Contract = <IERC20Metadata>(
            await ethers.getContractAt(CONTRACT_NAMES.IERC20Metadata, token0)
        );
        const token1Contract = <IERC20Metadata>(
            await ethers.getContractAt(CONTRACT_NAMES.IERC20Metadata, token1)
        );
        const token0Decimal = await token0Contract.decimals();
        const token1Decimal = await token1Contract.decimals();

        const reserve1 = BigNumber.from(
            reserveData[0]
                .mul(ichiPrice)
                .div(BigNumber.from(10).pow(token0Decimal))
        );
        const reserve2 = BigNumber.from(
            reserveData[1]
                .mul(usdcPrice)
                .div(BigNumber.from(10).pow(token1Decimal))
        );
        const lpPriceM = reserve1
            .add(reserve2)
            .mul(BigNumber.from(10).pow(18))
            .div(totalSupply);

        console.log("Manual Price:\t\t", utils.formatUnits(lpPriceM));

        expect(lpPrice.eq(lpPriceM)).to.be.true;
    });

    it("USDC/ICHI empty pool price", async () => {
        const LinkedLibFactory = await ethers.getContractFactory(
            "UniV3WrappedLib"
        );
        const LibInstance = await LinkedLibFactory.deploy();

        const IchiVault = await ethers.getContractFactory("MockIchiVault", {
            libraries: {
                UniV3WrappedLibMockup: LibInstance.address,
            },
        });
        const newVault = await IchiVault.deploy(
            ADDRESS.UNI_V3_ICHI_USDC,
            true,
            true,
            admin.address,
            admin.address,
            3600
        );

        const price = await ichiOracle.getPrice(newVault.address);
        expect(price).to.be.equal(0);
    });

    describe("Flashloan attack test", () => {
        it("Vault Reserve manipulation", async () => {
            // Prepare USDC
            // deposit 80 eth -> 80 WETH
            usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
            weth = <IWETH>(
                await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH)
            );
            await weth.deposit({value: utils.parseUnits("900")});

            // swap 40 weth -> usdc
            await weth.approve(
                ADDRESS.UNI_V2_ROUTER,
                ethers.constants.MaxUint256
            );
            const uniV2Router = <IUniswapV2Router02>(
                await ethers.getContractAt(
                    CONTRACT_NAMES.IUniswapV2Router02,
                    ADDRESS.UNI_V2_ROUTER
                )
            );
            await uniV2Router.swapExactTokensForTokens(
                utils.parseUnits("900"),
                0,
                [WETH, USDC],
                admin.address,
                ethers.constants.MaxUint256
            );
            console.log(
                "USDC Balance: ",
                utils.formatUnits(await usdc.balanceOf(admin.address), 6)
            );
            console.log("\n=== Before ===");
            const ichiPrice = await uniswapV3Oracle.getPrice(ADDRESS.ICHI);
            console.log("ICHI Price", utils.formatUnits(ichiPrice));

            let lpPrice = await ichiOracle.getPrice(ADDRESS.ICHI_VAULT_USDC);
            console.log(
                "USDC/ICHI Lp Price: \t",
                utils.formatUnits(lpPrice, 18)
            );

            await usdc.approve(ichiVault.address, ethers.constants.MaxUint256);

            console.log("\n=== Deposit $1,000 USDC on the ICHI Vault ===");
            await ichiVault.deposit(
                0,
                utils.parseUnits("1000", 6),
                admin.address
            );
            lpPrice = await ichiOracle.getPrice(ADDRESS.ICHI_VAULT_USDC);
            console.log(
                "USDC/ICHI Lp Price: \t",
                utils.formatUnits(lpPrice, 18)
            );

            console.log("\n=== Deposit $1,000,000 USDC on the ICHI Vault ===");
            await ichiVault.deposit(
                0,
                utils.parseUnits("1000000", 6),
                admin.address
            );
            lpPrice = await ichiOracle.getPrice(ADDRESS.ICHI_VAULT_USDC);
            console.log(
                "USDC/ICHI Lp Price: \t",
                utils.formatUnits(lpPrice, 18)
            );
        });

        it("Swap tokens on Uni V3 Pool to manipulate pool reserves", async () => {
            // Prepare USDC
            // deposit 80 eth -> 80 WETH
            usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
            weth = <IWETH>(
                await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH)
            );
            await weth.deposit({value: utils.parseUnits("900")});

            // swap 40 weth -> usdc
            await weth.approve(
                ADDRESS.UNI_V2_ROUTER,
                ethers.constants.MaxUint256
            );
            const uniV2Router = <IUniswapV2Router02>(
                await ethers.getContractAt(
                    CONTRACT_NAMES.IUniswapV2Router02,
                    ADDRESS.UNI_V2_ROUTER
                )
            );
            await uniV2Router.swapExactTokensForTokens(
                utils.parseUnits("900"),
                0,
                [WETH, USDC],
                admin.address,
                ethers.constants.MaxUint256
            );
            console.log(
                "USDC Balance: ",
                utils.formatUnits(await usdc.balanceOf(admin.address), 6)
            );
            console.log("\n=== Before ===");
            const ichiPrice = await uniswapV3Oracle.getPrice(ADDRESS.ICHI);
            console.log("ICHI Price", utils.formatUnits(ichiPrice));

            let lpPrice = await ichiOracle.getPrice(ADDRESS.ICHI_VAULT_USDC);
            console.log(
                "USDC/ICHI Lp Price: \t",
                utils.formatUnits(lpPrice, 18)
            );

            await usdc.approve(ichiVault.address, ethers.constants.MaxUint256);

            console.log("\n=== Deposit $1,000 USDC on the ICHI Vault ===");
            await ichiVault.deposit(
                0,
                utils.parseUnits("1000", 6),
                admin.address
            );
            lpPrice = await ichiOracle.getPrice(ADDRESS.ICHI_VAULT_USDC);
            console.log(
                "USDC/ICHI Lp Price: \t",
                utils.formatUnits(lpPrice, 18)
            );

            console.log("\n=== Deposit $1,000,000 USDC on the ICHI Vault ===");
            await ichiVault.deposit(
                0,
                utils.parseUnits("1000000", 6),
                admin.address
            );
            lpPrice = await ichiOracle.getPrice(ADDRESS.ICHI_VAULT_USDC);
            console.log(
                "USDC/ICHI Lp Price: \t",
                utils.formatUnits(lpPrice, 18)
            );
        });

        it("Test LP Price", async () => {
            await weth.deposit({value: utils.parseUnits("1000")});

            // swap 40 weth -> usdc
            await weth.approve(
                ADDRESS.UNI_V3_ROUTER,
                ethers.constants.MaxUint256
            );
            await swapRouter.exactInputSingle({
                tokenIn: WETH,
                tokenOut: USDC,
                fee: 3000,
                recipient: admin.address,
                deadline: Math.ceil(new Date().getTime() / 1000),
                amountIn: utils.parseUnits("1000"),
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0,
            });

            console.log("=== Before ===");
            let lpPrice = await ichiOracle.getPrice(ADDRESS.ICHI_VAULT_USDC);
            console.log(
                "USDC/ICHI Lp Price: \t",
                utils.formatUnits(lpPrice, 18)
            );

            await usdc.approve(
                ADDRESS.UNI_V3_ROUTER,
                ethers.constants.MaxUint256
            );
            // console.log("=========", await usdc.balanceOf(admin.address));
            await swapRouter.exactInputSingle({
                tokenIn: USDC,
                tokenOut: ICHI,
                fee: 10000,
                recipient: admin.address,
                deadline: Math.ceil(new Date().getTime() / 1000),
                amountIn: utils.parseUnits("1000000", 6),
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0,
            });

            console.log("=== After ===");
            lpPrice = await ichiOracle.getPrice(ADDRESS.ICHI_VAULT_USDC);
            console.log(
                "USDC/ICHI Lp Price: \t",
                utils.formatUnits(lpPrice, 18)
            );
        });
    });
});
554989243044.781131389288617288;
34431029956.131987060320315786;
