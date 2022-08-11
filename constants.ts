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

	// Uniswap
	MockUniswapV2Factory = "MockUniswapV2Factory",
	MockUniswapV2Router02 = "MockUniswapV2Router02",

	// Protocol
	HomoraBank = "HomoraBank",
	SafeBox = "SafeBox",
	SafeBoxETH = "SafeBoxETH",
	UniswapV2SpellV1 = "UniswapV2SpellV1",
}

export const ADDRESS = {
	// Tokens
	USDT: '0xdac17f958d2ee523a2206206994597c13d831ec7',
	USDC: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
	INDEX: '0x0954906da0Bf32d5479e25f46056d22f08464cab',
	PERP: '0xbC396689893D065F41bc2C6EcbeE5e0085233447',

	// LP
	UNI_V2_USDT_USDC: '0x3041cbd36888becc7bbcbc0045e3b1f144466f5f',

	// Oracle
	Keep3rV1Oracle: '0x73353801921417F465377c8d898c6f4C0270282C',

	// StdRef
	StdRef: '0xDA7a001b254CD22e46d3eAB04d937489c93174C3',

	// Wrapper
	SUSHI_MASTERCHEF: '0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd',
	CRV_GAUGE: '0x7D86446dDb609eD0F5f8684AcF30380a356b2B4c',

	// Index Coop
	IC_DPI_STAKING_REWARDS: '0xB93b505Ed567982E2b6756177ddD23ab5745f309',
	UNI_V2_DPI_WETH: '0x4d5ef58aAc27d99935E5b6B4A6778ff292059991',

	// Perpectual Protocol / Balancer
	PERP_BALANCER_LP_REWARDS: '0xb9840a4a8a671f79de3df3b812feeb38047ce552',
	BAL_PERP_USDC_POOL: '0xF54025aF2dc86809Be1153c1F20D77ADB7e8ecF4',
}