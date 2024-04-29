pragma solidity 0.5.16;

import "./PriceOracle.sol";
import "./interfaces/AggregatorV3Interface.sol";
import "./interfaces/V1PriceOracleInterface.sol";
import "../BErc20.sol";
import "../BToken.sol";
import "../Exponential.sol";
import "../EIP20Interface.sol";

contract PriceOracleProxyUSD is PriceOracle, Exponential {
    /// @notice ChainLink aggregator base, currently support USD and ETH
    enum AggregatorBase {
        USD,
        ETH
    }

    /// @notice Admin address
    address public admin;

    /// @notice Guardian address
    address public guardian;

    struct AggregatorInfo {
        /// @notice The source address of the aggregator
        AggregatorV3Interface source;
        /// @notice The aggregator base
        AggregatorBase base;
    }

    /// @notice Chainlink Aggregators
    mapping(address => AggregatorInfo) public aggregators;

    /// @notice Mapping of crToken to y-vault token
    mapping(address => address) public yVaults;

    /// @notice Mapping of crToken to curve swap
    mapping(address => address) public curveSwap;

    /// @notice The v1 price oracle, maintained by Blueberry
    V1PriceOracleInterface public v1PriceOracle;

    /// @notice The ETH-USD aggregator address
    AggregatorV3Interface public ethUsdAggregator;

    /**
     * @param admin_ The address of admin to set aggregators
     * @param v1PriceOracle_ The v1 price oracle
     */
    constructor(
        address admin_,
        address v1PriceOracle_,
        address ethUsdAggregator_
    ) public {
        admin = admin_;
        v1PriceOracle = V1PriceOracleInterface(v1PriceOracle_);
        ethUsdAggregator = AggregatorV3Interface(ethUsdAggregator_);
    }

    /**
     * @notice Get the underlying price of a listed bToken asset
     * @param bToken The bToken to get the underlying price of
     * @return The underlying asset price mantissa (scaled by 1e18)
     */
    function getUnderlyingPrice(BToken bToken) public view returns (uint256) {
        address bTokenAddress = address(bToken);

        AggregatorInfo memory aggregatorInfo = aggregators[bTokenAddress];
        if (address(aggregatorInfo.source) != address(0)) {
            uint256 price = getPriceFromChainlink(aggregatorInfo.source);
            if (aggregatorInfo.base == AggregatorBase.ETH) {
                // Convert the price to USD based if it's ETH based.
                price = mul_(
                    price,
                    Exp({mantissa: getPriceFromChainlink(ethUsdAggregator)})
                );
            }
            uint256 underlyingDecimals = EIP20Interface(
                BErc20(bTokenAddress).underlying()
            ).decimals();
            return mul_(price, 10**(18 - underlyingDecimals));
        }

        return getPriceFromV1(bTokenAddress);
    }

    /*** Internal fucntions ***/

    /**
     * @notice Get price from ChainLink
     * @param aggregator The ChainLink aggregator to get the price of
     * @return The price
     */
    function getPriceFromChainlink(AggregatorV3Interface aggregator)
        internal
        view
        returns (uint256)
    {
        (, int256 price, , , ) = aggregator.latestRoundData();
        require(price > 0, "invalid price");

        // Extend the decimals to 1e18.
        return mul_(uint256(price), 10**(18 - uint256(aggregator.decimals())));
    }

    /**
     * @notice Get price from v1 price oracle
     * @param bTokenAddress The BToken address
     * @return The price
     */
    function getPriceFromV1(address bTokenAddress)
        internal
        view
        returns (uint256)
    {
        address underlying = BErc20(bTokenAddress).underlying();
        return v1PriceOracle.assetPrices(underlying);
    }

    /*** Admin or guardian functions ***/

    event AggregatorUpdated(
        address bTokenAddress,
        address source,
        AggregatorBase base
    );
    event SetGuardian(address guardian);
    event SetAdmin(address admin);

    /**
     * @notice Set guardian for price oracle proxy
     * @param _guardian The new guardian
     */
    function _setGuardian(address _guardian) external {
        require(msg.sender == admin, "only the admin may set new guardian");
        guardian = _guardian;
        emit SetGuardian(guardian);
    }

    /**
     * @notice Set admin for price oracle proxy
     * @param _admin The new admin
     */
    function _setAdmin(address _admin) external {
        require(msg.sender == admin, "only the admin may set new admin");
        admin = _admin;
        emit SetAdmin(admin);
    }

    /**
     * @notice Set ChainLink aggregators for multiple bTokens
     * @param bTokenAddresses The list of bTokens
     * @param sources The list of ChainLink aggregator sources
     * @param bases The list of ChainLink aggregator bases
     */
    function _setAggregators(
        address[] calldata bTokenAddresses,
        address[] calldata sources,
        AggregatorBase[] calldata bases
    ) external {
        require(
            msg.sender == admin || msg.sender == guardian,
            "only the admin or guardian may set the aggregators"
        );
        require(
            bTokenAddresses.length == sources.length &&
                bTokenAddresses.length == bases.length,
            "mismatched data"
        );
        for (uint256 i = 0; i < bTokenAddresses.length; i++) {
            AggregatorV3Interface source = AggregatorV3Interface(sources[i]);
            
            if (sources[i] != address(0)) {
                require(
                    msg.sender == admin,
                    "guardian may only clear the aggregator"
                );

                require(
                    bases[i] == AggregatorBase.USD ||
                        bases[i] == AggregatorBase.ETH,
                    "aggregator base may only be USD or ETH"
                );

                (, int256 answer,,,) = source.latestRoundData();
                require(
                    answer > 0,
                    "invalid pricing aggregator"
                );
            }

            aggregators[bTokenAddresses[i]] = AggregatorInfo({
                source: source,
                base: bases[i]
            });
            emit AggregatorUpdated(bTokenAddresses[i], sources[i], bases[i]);
        }
    }
}