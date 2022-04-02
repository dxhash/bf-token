// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct AppStorage {
    string name;
    string symbol;
    uint8 decimals;
    string currency;
    uint256 totalSupply;
    bool paused;
    address blacklister;
    address pauser;
    address rescuer;
    bytes32 DOMAIN_SEPARATOR;
    mapping(address => uint256) balances;
    mapping(address => mapping(address => uint256)) allowed;
    mapping(address => bool) minters;
    mapping(address => uint256) minterAllowed;
    mapping(address => bool) blacklisted;
    mapping(address => uint256) permitNonces;
    bytes32 PERMIT_TYPEHASH;
    bytes32 TRANSFER_WITH_AUTHORIZATION_TYPEHASH; /* */
    bytes32 RECEIVE_WITH_AUTHORIZATION_TYPEHASH;
    bytes32 CANCEL_AUTHORIZATION_TYPEHASH;
    mapping(address => mapping(bytes32 => bool)) _authorizationStates;
}

library LibAppStorage {
    function diamondStorage() internal pure returns (AppStorage storage ds_) {
        assembly {
            ds_.slot := 0
        }
    }

    function abs(int256 x) internal pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }
}
