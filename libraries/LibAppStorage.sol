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
    mapping(address => uint256) balances;
    mapping(address => mapping(address => uint256)) allowed;
    mapping(address => bool) minters;
    mapping(address => uint256) minterAllowed;
    mapping(address => bool) blacklisted;
    mapping(address => uint256) permitNonces;
    mapping(address => mapping(bytes32 => bool)) _authorizationStates;
}
