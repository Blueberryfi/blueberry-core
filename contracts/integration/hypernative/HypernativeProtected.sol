// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { ECDSAUpgradeable as ECDSA } from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

abstract contract HypernativeProtected {
    using ECDSA for bytes32;
    address internal _hypernativeSigner;

    error InvalidSignature();

    modifier verifyHypernativeTx(bytes32 hash, bytes memory _signature) {
        address _signer = hash.recover(_signature);
        require(_signer == _hypernativeSigner, "HypernativeProtector: Invalid signature");
        _;
    }
}
