// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IDiamondLoupe} from "../interfaces/IDiamondLoupe.sol";
import {IDiamondCut} from "../interfaces/IDiamondCut.sol";
import {IERC165} from "../interfaces/IERC165.sol";
import {IERC173} from "../interfaces/IERC173.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IEIP2612} from "../interfaces/IEIP2612.sol";
import {IEIP3009} from "../interfaces/IEIP3009.sol";

contract DiamondInit {
    function init() external {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ds.supportedInterfaces[type(IERC173).interfaceId] = true;
        ds.supportedInterfaces[type(IERC20).interfaceId] = true;
        ds.supportedInterfaces[type(IEIP3009).interfaceId] = true;
        ds.supportedInterfaces[type(IEIP2612).interfaceId] = true;
    }
}
