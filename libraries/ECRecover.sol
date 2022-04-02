// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library ECRecover {
    function recover(
        bytes32 digest,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address) {
        if (
            uint256(s) >
            0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0
        ) {
            revert("Invalid signature 's' value");
        }

        if (v != 27 && v != 28) {
            revert("Invalid signature 'v' value");
        }

        address signer = ecrecover(digest, v, r, s);
        require(signer != address(0), "Invalid signature");

        return signer;
    }
}
