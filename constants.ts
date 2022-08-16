export enum CONTRACT_NAMES {
	// Token
	ERC20 = "ERC20",
	IERC20 = "IERC20",
	MockWETH = "MockWETH",
	MockERC20 = "MockERC20",
	MockCErc20 = "MockCErc20",
	MockCErc20_2 = "MockCErc20_2",

	// Wrapper
	WERC20 = "WERC20",
	WMasterChef = "WMasterChef",
	WLiquidityGauge = "WLiquidityGauge",
	WStakingRewards = "WStakingRewards",

	// Oracles
	SimpleOracle = "SimpleOracle",
	CoreOracle = "CoreOracle",
	ProxyOracle = "ProxyOracle",
	UniswapV2Oracle = "UniswapV2Oracle",
	BalancerPairOracle = "BalancerPairOracle",
	ERC20KP3ROracle = "ERC20KP3ROracle",
	CurveOracle = "CurveOracle",
	UniswapV3AdapterOracle = "UniswapV3AdapterOracle",
	AggregatorOracle = "AggregatorOracle",

	// Uniswap
	MockUniswapV2Factory = "MockUniswapV2Factory",
	MockUniswapV2Router02 = "MockUniswapV2Router02",

	// Protocol
	BlueBerryBank = "BlueBerryBank",
	SafeBox = "SafeBox",
	SafeBoxETH = "SafeBoxETH",

	// Spell
	UniswapV2SpellV1 = "UniswapV2SpellV1",
	SushiswapSpellV1 = "SushiswapSpellV1",
	BalancerSpellV1 = "BalancerSpellV1",
	CurveSpellV1 = "CurveSpellV1",

	// Interface
	IComptroller = "IComptroller",
	ICEtherEx = "ICEtherEx",
	ICErc20 = "ICErc20",
	ICurvePool = "ICurvePool",
	ICurveRegistry = "ICurveRegistry",
	IERC20Ex = "IERC20Ex",
	IUniswapV2Pair = "IUniswapV2Pair",
	IUniswapV3Pool = "IUniswapV3Pool",
}

export const ADDRESS = {
	// Tokens
	DAI: '0x6b175474e89094c44da98b954eedeac495271d0f',
	DPI: '0x1494ca1f11d487c2bbe4543e90080aeba4ba3c2b',
	ETH: '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE',
	INDEX: '0x0954906da0Bf32d5479e25f46056d22f08464cab',
	PERP: '0xbC396689893D065F41bc2C6EcbeE5e0085233447',
	SNX: '0xc011a73ee8576fb46f5e1c5751ca3b9fe0af2a6f',
	USDT: '0xdac17f958d2ee523a2206206994597c13d831ec7',
	USDC: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
	WBTC: '0x2260fac5e5542a773aa44fbcfedf7c193bc2c599',
	WETH: '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2',
	crDAI: '0x92B767185fB3B04F881e3aC8e5B0662a027A1D9f',
	crUSDC: '0x44fbebd2f576670a6c33f6fc0b00aa8c5753b322',
	crUSDT: '0x797AAB1ce7c01eB727ab980762bA88e7133d2157',
	UNI: '0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984',

	// LP
	UNI_V2_USDT_USDC: '0x3041cbd36888becc7bbcbc0045e3b1f144466f5f',
	UNI_V2_DPI_WETH: '0x4d5ef58aAc27d99935E5b6B4A6778ff292059991',
	UNI_V2_DAI_WETH: '0xa478c2975ab1ea89e8196811f51a7b7ade33eb11',
	UNI_V2_USDT_WETH: '0x0d4a11d5eeaac28ec3f61d100daf4d40471f1852',
	UNI_V2_USDC_WETH: '0xb4e16d0168e52d35cacd2c6185b44281ec28c9dc',
	UNI_V2_WBTC_WETH: '0xbb2b8038a1640196fbe3e38816f3e67cba72d940',
	SUSHI_WETH_USDT: '0x06da0fd433c1a5d7a4faa01111c044910a184553',
	BAL_WETH_DAI_8020: '0x8b6e6e7b5b3801fed2cafd4b22b8a16c2f2db21a',
	BAL_PERP_USDC_8020: '0xF54025aF2dc86809Be1153c1F20D77ADB7e8ecF4',
	CRV_3Crv: '0x6c3f90f043a72fa612cbac8115ee7e52bde6e490',
	UNI_V3_UNI_WETH: '0x1d42064fc4beb5f8aaf85f4617ae8b3b5b8bd801',
	UNI_V3_UNI_USDC: '0xd0fc8ba7e267f2bc56044a7715a489d851dc6d78',

	// Oracle
	Keep3rV1Oracle: '0x73353801921417F465377c8d898c6f4C0270282C',

	// StdRef
	StdRef: '0xDA7a001b254CD22e46d3eAB04d937489c93174C3',

	UNI_V2_ROUTER: '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D',
	SUSHI_ROUTER: '0xd9e1ce17f2641f24ae83637ab66a2cca9c378b9f',

	// Wrapper
	SUSHI_MASTERCHEF: '0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd',
	CRV_GAUGE: '0x7D86446dDb609eD0F5f8684AcF30380a356b2B4c',
	CRV_3Crv_POOL: '0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7',
	IC_DPI_STAKING_REWARDS: '0xB93b505Ed567982E2b6756177ddD23ab5745f309',
	PERP_BALANCER_LP_REWARDS: '0xb9840a4a8a671f79de3df3b812feeb38047ce552',
}