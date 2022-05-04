// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ECRecover.sol";

library EIP712 {
    event RecoverDebug(bytes data);
    event RecoverDebug32(bytes32 data);

    function recover(
        bytes32 domainSeparator,
        uint8 v,
        bytes32 r,
        bytes32 s,
        bytes memory typeHashAndData
    ) internal pure returns (address) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(typeHashAndData)
            )
        );

        return ECRecover.recover(digest, v, r, s);
    }
}
