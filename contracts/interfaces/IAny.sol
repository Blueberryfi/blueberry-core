pragma solidity ^0.8.9;

interface IAny {
    function approve(address, uint256) external;

    function _setCreditLimit(address, uint256) external;

    function setOracle(address) external;

    function poolInfo(uint256)
        external
        view
        returns (
            address,
            uint256,
            uint256,
            uint256
        );

    function poolLength() external view returns (uint256);

    function setWhitelistSpells(address[] memory, bool[] memory) external;

    function setWhitelistTokens(address[] memory, bool[] memory) external;

    function getPrice(address, address)
        external
        view
        returns (uint256, uint256);

    function owner() external view returns (address);

    function work(
        uint256,
        address,
        uint256,
        uint256,
        bytes memory
    ) external;

    function setPrices(
        address[] memory,
        address[] memory,
        uint256[] memory
    ) external;

    function getETHPx(address) external view returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function admin() external view returns (address);

    function getPositionInfo(uint256)
        external
        view
        returns (
            address,
            address,
            uint256,
            uint256
        );

    function getUnderlyingToken(uint256) external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    function totalSupply() external view returns (uint256);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function decimals() external view returns (uint256);

    function symbol() external view returns (string memory);

    function exchangeRateStored() external view returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function borrowBalanceStored(address) external view returns (uint256);

    function borrowBalanceCurrent(address) external returns (uint256);

    function accrueInterest() external returns (uint256);
}
