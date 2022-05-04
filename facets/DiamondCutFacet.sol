// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IDiamondCut} from "../interfaces/IDiamondCut.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";

contract DiamondCutFacet is IDiamondCut {
    function diamondCut(
        uint8[] memory _sigV,
        bytes32[] memory _sigR,
        bytes32[] memory _sigS,
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external {
        bytes memory data = abi.encode(
            /* keccak256("diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata)") */
            0x341ab194e947b7a2a3d70d413e4359c3d7a5c0b0c57bc65fe82d27b529ea1102,
            _diamondCut,
            _init,
            _calldata,
            LibDiamond.configNonce()
        );

        LibDiamond.verifySignature(_sigV, _sigR, _sigS, data);

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 originalSelectorCount = ds.selectorCount;
        uint256 selectorCount = originalSelectorCount;
        bytes32 selectorSlot;
        if (selectorCount & 7 > 0) {
            selectorSlot = ds.selectorSlots[selectorCount >> 3];
        }
        for (
            uint256 facetIndex;
            facetIndex < _diamondCut.length;
            facetIndex++
        ) {
            (selectorCount, selectorSlot) = LibDiamond
                .addReplaceRemoveFacetSelectors(
                    selectorCount,
                    selectorSlot,
                    _diamondCut[facetIndex].facetAddress,
                    _diamondCut[facetIndex].action,
                    _diamondCut[facetIndex].functionSelectors
                );
        }
        if (selectorCount != originalSelectorCount) {
            ds.selectorCount = uint16(selectorCount);
        }

        if (selectorCount & 7 > 0) {
            ds.selectorSlots[selectorCount >> 3] = selectorSlot;
        }
        emit DiamondCut(_diamondCut, _init, _calldata);
        LibDiamond.initializeDiamondCut(_init, _calldata);
    }
}
