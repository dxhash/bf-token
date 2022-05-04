// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {AppStorage} from "../libraries/LibAppStorage.sol";

contract OwnershipFacet {
    /* keccak256("setContractOwners(address[] memory _newOwners, uint8 _threshold)") */
    bytes32 internal constant _SET_CONTRACT_OWNERS_TYPEHASH =
        0xeaa345ccada478cb9ef1cc330b0af567dfc253db6a392af6825af2ea8ccf900d;

    function setContractOwnersWithAuthorization(
        address[] memory _newOwners,
        uint8 _threshold,
        uint8[] memory _sigV,
        bytes32[] memory _sigR,
        bytes32[] memory _sigS
    ) public {
        bytes memory data = abi.encode(
            _SET_CONTRACT_OWNERS_TYPEHASH,
            _newOwners,
            _threshold,
            LibDiamond.configNonce()
        );

        LibDiamond.verifySignature(_sigV, _sigR, _sigS, data);
        LibDiamond.setContractOwners(_newOwners, _threshold);
    }
}
