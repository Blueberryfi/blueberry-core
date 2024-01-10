pragma solidity 0.5.16;

import "./BToken.sol";
import "./ComptrollerStorage.sol";

interface ComptrollerInterfaceExtension {
    function checkMembership(address account, BToken bToken)
        external
        view
        returns (bool);

    function updateBTokenVersion(
        address bToken,
        ComptrollerV1Storage.Version version
    ) external;

    function flashloanAllowed(
        address bToken,
        address receiver,
        uint256 amount,
        bytes calldata params
    ) external view returns (bool);

    function getAccountLiquidity(address account)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    function supplyCaps(address market) external view returns (uint256);
}
