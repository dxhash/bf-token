// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

/******************************************************************************\
* Based on implementation of a diamond by Nick Mudge (https://twitter.com/mudgen)
* EIP-2535 Diamond Standard: https://eips.ethereum.org/EIPS/eip-2535
/******************************************************************************/

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IDiamondLoupe} from "../interfaces/IDiamondLoupe.sol";
import {IERC165} from "../interfaces/IERC165.sol";

contract DiamondLoupeFacet is IDiamondLoupe, IERC165 {
    function facets() external view override returns (Facet[] memory facets_) {
        facets_ = _facets(0, 0);
    }

    function facets(uint256 _slotIndex, uint256 _selectorCount)
        external
        view
        returns (Facet[] memory facets_)
    {
        facets_ = _facets(_slotIndex, _selectorCount);
    }

    /**
     * @dev These functions are expected to be called frequently by tools.
     *
     * struct Facet {
     *     address facetAddress;
     *     bytes4[] functionSelectors;
     * }
     * @notice Gets all facets and their selectors.
     * @param _slotIndex The slot index.
     * @param _selectorCount Selectors count.
     * @return facets_ Facet
     */

    function _facets(uint256 _slotIndex, uint256 _selectorCount)
        internal
        view
        returns (Facet[] memory facets_)
    {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        if (_selectorCount == 0) {
            _selectorCount = ds.selectorCount;
        }

        facets_ = new Facet[](_selectorCount);
        // Prevent adding more Facetselectors than uint16:MAX
        uint16[] memory numFacetSelectors = new uint16[](_selectorCount);
        uint256 numFacets;
        uint256 selectorIndex;
        // loop through function selectors
        for (_slotIndex; selectorIndex < _selectorCount; _slotIndex++) {
            bytes32 slot = ds.selectorSlots[_slotIndex];
            for (
                uint256 selectorSlotIndex;
                selectorSlotIndex < 8;
                selectorSlotIndex++
            ) {
                selectorIndex++;
                if (selectorIndex > _selectorCount) {
                    break;
                }
                bytes4 selector = bytes4(slot << (selectorSlotIndex << 5));
                address facetAddress_ = address(bytes20(ds.facets[selector]));
                bool continueLoop = false;
                for (uint256 facetIndex; facetIndex < numFacets; facetIndex++) {
                    if (facets_[facetIndex].facetAddress == facetAddress_) {
                        facets_[facetIndex].functionSelectors[
                            numFacetSelectors[facetIndex]
                        ] = selector;
                        require(numFacetSelectors[facetIndex] < 0xffff);
                        numFacetSelectors[facetIndex]++;
                        continueLoop = true;
                        break;
                    }
                }
                if (continueLoop) {
                    continueLoop = false;
                    continue;
                }
                facets_[numFacets].facetAddress = facetAddress_;
                facets_[numFacets].functionSelectors = new bytes4[](
                    _selectorCount
                );
                facets_[numFacets].functionSelectors[0] = selector;
                numFacetSelectors[numFacets] = 1;
                numFacets++;
            }
        }
        for (uint256 facetIndex; facetIndex < numFacets; facetIndex++) {
            uint256 numSelectors = numFacetSelectors[facetIndex];
            bytes4[] memory selectors = facets_[facetIndex].functionSelectors;
            // setting the number of selectors
            assembly {
                mstore(selectors, numSelectors)
            }
        }
        // setting the number of facets
        assembly {
            mstore(facets_, numFacets)
        }
    }

    function facetFunctionSelectors(address _facet)
        external
        view
        override
        returns (bytes4[] memory facetFunctionSelectors_)
    {
        facetFunctionSelectors_ = _facetFunctionSelectors(_facet, 0, 0);
    }

    function facetFunctionSelectors(
        address _facet,
        uint256 _slotIndex,
        uint256 _selectorCount
    ) external view returns (bytes4[] memory facetFunctionSelectors_) {
        facetFunctionSelectors_ = _facetFunctionSelectors(
            _facet,
            _slotIndex,
            _selectorCount
        );
    }

    /**
     * @notice Gets all the function selectors supported by a specific facet.
     * @param _facet The facet address.
     * @return facetFunctionSelectors_ The selectors associated with a facet address.
     */

    function _facetFunctionSelectors(
        address _facet,
        uint256 _slotIndex,
        uint256 _selectorCount
    ) internal view returns (bytes4[] memory facetFunctionSelectors_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        if (_selectorCount == 0) {
            _selectorCount = ds.selectorCount;
        }

        uint256 numSelectors;
        facetFunctionSelectors_ = new bytes4[](_selectorCount);
        uint256 selectorIndex;
        // loop through function selectors
        for (_slotIndex; selectorIndex < _selectorCount; _slotIndex++) {
            bytes32 slot = ds.selectorSlots[_slotIndex];
            for (
                uint256 selectorSlotIndex;
                selectorSlotIndex < 8;
                selectorSlotIndex++
            ) {
                selectorIndex++;
                if (selectorIndex > _selectorCount) {
                    break;
                }
                bytes4 selector = bytes4(slot << (selectorSlotIndex << 5));
                address facet = address(bytes20(ds.facets[selector]));
                if (_facet == facet) {
                    facetFunctionSelectors_[numSelectors] = selector;
                    numSelectors++;
                }
            }
        }
        // Set the number of selectors in the array
        assembly {
            mstore(facetFunctionSelectors_, numSelectors)
        }
    }

    function facetAddresses()
        external
        view
        override
        returns (address[] memory facetAddresses_)
    {
        facetAddresses_ = _facetAddresses(0, 0);
    }

    function facetAddresses(uint256 _slotIndex, uint256 _selectorCount)
        external
        view
        returns (address[] memory facetAddresses_)
    {
        facetAddresses_ = _facetAddresses(_slotIndex, _selectorCount);
    }

    /**
     * @notice Get all the facet addresses used by a diamond.
     * @return facetAddresses_
     */

    function _facetAddresses(uint256 _slotIndex, uint256 _selectorCount)
        internal
        view
        returns (address[] memory facetAddresses_)
    {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        if (_selectorCount == 0) {
            _selectorCount = ds.selectorCount;
        }

        facetAddresses_ = new address[](_selectorCount);
        uint256 numFacets;
        uint256 selectorIndex;
        // loop through function selectors
        for (_slotIndex; selectorIndex < _selectorCount; _slotIndex++) {
            bytes32 slot = ds.selectorSlots[_slotIndex];
            for (
                uint256 selectorSlotIndex;
                selectorSlotIndex < 8;
                selectorSlotIndex++
            ) {
                selectorIndex++;
                if (selectorIndex > _selectorCount) {
                    break;
                }
                bytes4 selector = bytes4(slot << (selectorSlotIndex << 5));
                address facetAddress_ = address(bytes20(ds.facets[selector]));
                bool continueLoop = false;
                for (uint256 facetIndex; facetIndex < numFacets; facetIndex++) {
                    if (facetAddress_ == facetAddresses_[facetIndex]) {
                        continueLoop = true;
                        break;
                    }
                }
                if (continueLoop) {
                    continueLoop = false;
                    continue;
                }
                facetAddresses_[numFacets] = facetAddress_;
                numFacets++;
            }
        }
        // Set the number of facet addresses in the array
        assembly {
            mstore(facetAddresses_, numFacets)
        }
    }

    /**
     * @notice Gets the facet that supports the given selector.
     * @dev If facet is not found return address(0).
     * @param _functionSelector The function selector.
     * @return facetAddress_ The facet address.
     */

    function facetAddress(bytes4 _functionSelector)
        external
        view
        override
        returns (address facetAddress_)
    {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        facetAddress_ = address(bytes20(ds.facets[_functionSelector]));
    }

    /**
     * @dev This implements ERC-165.
     * @param _interfaceId The interface identifier, as specified in ERC-165
     * @return `true` if the contract implements `interfaceID`, `false` otherwise
     */

    function supportsInterface(bytes4 _interfaceId)
        external
        view
        override
        returns (bool)
    {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return ds.supportedInterfaces[_interfaceId];
    }
}
