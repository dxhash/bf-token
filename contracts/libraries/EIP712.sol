// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ECRecover} from "./ECRecover.sol";

/**
 * @title EIP712
 * @notice A library that provides EIP712 helper functions
 */

library EIP712 {
    /**
     * @notice Make EIP712 domain separator
     * @param name      Contract name
     * @param version   Contract version
     * @return Domain separator
     */
    function makeDomainSeparator(string memory name, string memory version)
        internal
        view
        returns (bytes32)
    {
        return
            keccak256(
                abi.encode(
                    // keccak256("EIP712Domain(string _name,string _version,uint256 _chainId,address _verifyingContract)")
                    0xbc401e48a390421e8786d72c7fd44afeed5af1075ecfef31ed40894bdb0e96a5,
                    keccak256(bytes(name)),
                    keccak256(bytes(version)),
                    block.chainid,
                    address(this)
                )
            );
    }

    /**
     * @notice Recover signer's address from a EIP712 signature
     * @param domainSeparator   Domain separator
     * @param v                 v of the signature
     * @param r                 r of the signature
     * @param s                 s of the signature
     * @param typeHashAndData   Type hash concatenated with data
     * @return Signer's address
     */
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
