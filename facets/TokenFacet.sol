// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "../interfaces/IERC20.sol";
import {SafeERC20} from "../libraries/SafeERC20.sol";
import {EIP712} from "../libraries/EIP712.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {AppStorage} from "../libraries/LibAppStorage.sol";

contract TokenFacet is IERC20 {
    AppStorage internal s;

    using SafeERC20 for IERC20;
    bool internal _initialized;

    event TokenSetup(
        address indexed initiator,
        string _name,
        string _token,
        uint8 decimals
    );
    event Mint(address indexed minter, address indexed to, uint256 amount);
    event Burn(address indexed burner, uint256 amount);
    event MinterConfigured(address indexed minter, uint256 minterAllowedAmount);
    event MinterRemoved(address indexed oldMinter);

    /* keccak256("Permit(address _owner,address _spender,uint256 _value,uint256 _nonce,uint256 _deadline)") */
    bytes32 internal constant _PERMIT_TYPEHASH =
        0x283ef5f1323e8965c0333bc5843eb0b8d7ffe23b9c2eab15c3e3ffcc75ae8134;

    /* keccak256("TransferWithAuthorization(address _from,address _to,uint256 _value,uint256 _validAfter,uint256 _validBefore,bytes32 _nonce)")*/
    bytes32 internal constant _TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
        0x310777934f929c98189a844bb5f21f2844db2a576625365b824861540a319f79;

    /* keccak256("ReceiveWithAuthorization(address _from,address _to,uint256 _value,uint256 _validAfter,uint256 _validBefore,bytes32 _nonce)")*/
    bytes32 internal constant _RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
        0x58ac3df019d91fe0955489460a6a1c370bec91d993d7efbc0925fe3d403653eb;

    /* keccak256("CancelAuthorization(address _authorizer,bytes32 _nonce)")*/
    bytes32 internal constant _CANCEL_AUTHORIZATION_TYPEHASH =
        0xf523c75f846f1f78c4e7be3cf73d7e9c0b2a8d15cd65153faae8afa14f91c341;

    function name() external view returns (string memory name_) {
        name_ = s.name;
    }

    function symbol() external view returns (string memory symbol_) {
        symbol_ = s.symbol;
    }

    function decimals() external view returns (uint8 decimals_) {
        decimals_ = s.decimals;
    }

    function PERMIT_TYPEHASH() external pure returns (bytes32 pth_) {
        pth_ = _PERMIT_TYPEHASH;
    }

    function TRANSFER_WITH_AUTHORIZATION_TYPEHASH()
        external
        pure
        returns (bytes32 twath_)
    {
        twath_ = _TRANSFER_WITH_AUTHORIZATION_TYPEHASH;
    }

    function RECEIVE_WITH_AUTHORIZATION_TYPEHASH()
        external
        pure
        returns (bytes32 rwath_)
    {
        rwath_ = _RECEIVE_WITH_AUTHORIZATION_TYPEHASH;
    }

    function CANCEL_AUTHORIZATION_TYPEHASH()
        external
        pure
        returns (bytes32 cath_)
    {
        cath_ = _CANCEL_AUTHORIZATION_TYPEHASH;
    }

    constructor() {
        _initialized = false;
    }

    function setup(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint8[] memory _sigV,
        bytes32[] memory _sigR,
        bytes32[] memory _sigS
    ) external {
        require(!_initialized);

        bytes memory data = abi.encode(
            /* keccak256("setup(string memory _name, string memory _symbol, uint8 _decimals)") */
            0x51a2bedc1562aee1534c78539fe723856c03df65743a62d6c4c4846832e3c862,
            _name,
            _symbol,
            _decimals,
            LibDiamond.configNonce()
        );

        LibDiamond.verifySignature(_sigV, _sigR, _sigS, data);

        s.name = _name;
        s.symbol = _symbol;
        s.decimals = _decimals;

        _initialized = true;
        emit TokenSetup(msg.sender, _name, _symbol, _decimals);
    }

    modifier onlyMinters() {
        require(s.minters[msg.sender], "Caller is not a minter");
        _;
    }

    function mint(address _to, uint256 _amount)
        external
        whenNotPaused
        onlyMinters
        notBlacklisted(msg.sender)
        notBlacklisted(_to)
        returns (bool)
    {
        require(_to != address(0), "Mint to the zero address");
        require(_amount > 0, "Mint amount not greater than 0");

        uint256 mintingAllowedAmount = s.minterAllowed[msg.sender];
        require(
            _amount <= mintingAllowedAmount,
            "Mint amount exceeds minterAllowance"
        );

        s.totalSupply = s.totalSupply + _amount;
        s.balances[_to] = s.balances[_to] + _amount;
        s.minterAllowed[msg.sender] = mintingAllowedAmount - _amount;
        emit Mint(msg.sender, _to, _amount);
        emit Transfer(address(0), _to, _amount);
        return true;
    }

    function minterAllowance(address _minter)
        external
        view
        returns (uint256 amount_)
    {
        amount_ = s.minterAllowed[_minter];
    }

    function isMinter(address _account) external view returns (bool isMinter_) {
        isMinter_ = s.minters[_account];
    }

    function allowance(address _owner, address _spender)
        external
        view
        returns (uint256 amount_)
    {
        amount_ = s.allowed[_owner][_spender];
    }

    function totalSupply() external view returns (uint256 amount_) {
        amount_ = s.totalSupply;
    }

    function balanceOf(address _account)
        external
        view
        returns (uint256 amount_)
    {
        amount_ = s.balances[_account];
    }

    function approve(address _spender, uint256 _value)
        external
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(_spender)
        returns (bool)
    {
        _approve(msg.sender, _spender, _value);
        return true;
    }

    function _approve(
        address _owner,
        address _spender,
        uint256 _value
    ) internal {
        require(_owner != address(0), "Approve from the zero address");
        require(_spender != address(0), "Approve to the zero address");
        s.allowed[_owner][_spender] = _value;
        emit Approval(_owner, _spender, _value);
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    )
        external
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(_from)
        notBlacklisted(_to)
        returns (bool)
    {
        require(
            _value <= s.allowed[_from][msg.sender],
            "Transfer amount exceeds allowance"
        );
        _transfer(_from, _to, _value);
        s.allowed[_from][msg.sender] = s.allowed[_from][msg.sender] - _value;
        return true;
    }

    function transfer(address _to, uint256 _value)
        external
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(_to)
        returns (bool)
    {
        _transfer(msg.sender, _to, _value);
        return true;
    }

    function _transfer(
        address _from,
        address _to,
        uint256 _value
    ) internal {
        require(_from != address(0), "Transfer from the zero address");
        require(_to != address(0), "Transfer to the zero address");
        require(_value <= s.balances[_from], "Transfer amount exceeds balance");

        s.balances[_from] = s.balances[_from] - _value;
        s.balances[_to] = s.balances[_to] + _value;
        emit Transfer(_from, _to, _value);
    }

    function configureMinter(
        address _minter,
        uint256 _minterAllowedAmount,
        uint8[] memory _sigV,
        bytes32[] memory _sigR,
        bytes32[] memory _sigS
    ) external whenNotPaused returns (bool) {
        bytes memory data = abi.encode(
            /* keccak256("configureMinter(address _minter, uint256 _minterAllowedAmount)") */
            0xfb07eab7876ee8bf1e34912fcc5565e508ad409816590c97cc6066de797e7782,
            _minter,
            _minterAllowedAmount,
            LibDiamond.configNonce()
        );

        LibDiamond.verifySignature(_sigV, _sigR, _sigS, data);

        s.minters[_minter] = true;
        s.minterAllowed[_minter] = _minterAllowedAmount;
        emit MinterConfigured(_minter, _minterAllowedAmount);
        return true;
    }

    function removeMinter(
        address _minter,
        uint8[] memory _sigV,
        bytes32[] memory _sigR,
        bytes32[] memory _sigS
    ) external returns (bool) {
        bytes memory data = abi.encode(
            /* keccak256("removeMinter(address _minter)") */
            0xb35670b45083259ff8fcf0c8be2c81d0e0ab8d77b9983a6eda5f3895a12f82d0,
            _minter,
            LibDiamond.configNonce()
        );

        LibDiamond.verifySignature(_sigV, _sigR, _sigS, data);

        s.minters[_minter] = false;
        s.minterAllowed[_minter] = 0;
        emit MinterRemoved(_minter);
        return true;
    }

    function burn(uint256 _amount)
        external
        whenNotPaused
        notBlacklisted(msg.sender)
    {
        uint256 balance = s.balances[msg.sender];
        require(_amount > 0, "Burn amount not greater than 0");
        require(balance >= _amount, "Burn amount exceeds balance");

        s.totalSupply = s.totalSupply - _amount;
        s.balances[msg.sender] = balance - _amount;
        emit Burn(msg.sender, _amount);
        emit Transfer(msg.sender, address(0), _amount);
    }

    function increaseAllowance(address _spender, uint256 _increment)
        external
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(_spender)
        returns (bool)
    {
        _increaseAllowance(msg.sender, _spender, _increment);
        return true;
    }

    function decreaseAllowance(address _spender, uint256 _decrement)
        external
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(_spender)
        returns (bool)
    {
        _decreaseAllowance(msg.sender, _spender, _decrement);
        return true;
    }

    function transferWithAuthorization(
        address _from,
        address _to,
        uint256 _value,
        uint256 _validAfter,
        uint256 _validBefore,
        bytes32 _nonce,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external whenNotPaused notBlacklisted(_from) notBlacklisted(_to) {
        _transferWithAuthorization(
            _from,
            _to,
            _value,
            _validAfter,
            _validBefore,
            _nonce,
            _v,
            _r,
            _s
        );
    }

    function receiveWithAuthorization(
        address _from,
        address _to,
        uint256 _value,
        uint256 _validAfter,
        uint256 _validBefore,
        bytes32 _nonce,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external whenNotPaused notBlacklisted(_from) notBlacklisted(_to) {
        _receiveWithAuthorization(
            _from,
            _to,
            _value,
            _validAfter,
            _validBefore,
            _nonce,
            _v,
            _r,
            _s
        );
    }

    function cancelAuthorization(
        address _authorizer,
        bytes32 _nonce,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external whenNotPaused {
        _cancelAuthorization(_authorizer, _nonce, _v, _r, _s);
    }

    function permit(
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external whenNotPaused notBlacklisted(_owner) notBlacklisted(_spender) {
        _permit(_owner, _spender, _value, _deadline, _v, _r, _s);
    }

    function _increaseAllowance(
        address _owner,
        address _spender,
        uint256 _increment
    ) internal {
        _approve(_owner, _spender, s.allowed[_owner][_spender] + _increment);
    }

    function _decreaseAllowance(
        address _owner,
        address _spender,
        uint256 _decrement
    ) internal {
        _approve(_owner, _spender, s.allowed[_owner][_spender] - _decrement);
    }

    function nonces(address _owner) external view returns (uint256 nonce_) {
        nonce_ = s.permitNonces[_owner];
    }

    function _permit(
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) internal {
        require(_deadline >= block.timestamp, "Permit is expired");

        bytes memory data = abi.encode(
            _PERMIT_TYPEHASH,
            _owner,
            _spender,
            _value,
            s.permitNonces[_owner]++,
            _deadline
        );
        require(
            EIP712.recover(LibDiamond.domainSeparator(), _v, _r, _s, data) ==
                _owner,
            "Invalid signature"
        );

        _approve(_owner, _spender, _value);
    }

    mapping(address => mapping(bytes32 => bool)) private _authorizationStates;

    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
    event AuthorizationCanceled(
        address indexed authorizer,
        bytes32 indexed nonce
    );

    function authorizationState(address _authorizer, bytes32 _nonce)
        external
        view
        returns (bool state_)
    {
        state_ = _authorizationStates[_authorizer][_nonce];
    }

    function _transferWithAuthorization(
        address _from,
        address _to,
        uint256 _value,
        uint256 _validAfter,
        uint256 _validBefore,
        bytes32 _nonce,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) internal {
        _requireValidAuthorization(_from, _nonce, _validAfter, _validBefore);

        bytes memory data = abi.encode(
            _TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
            _from,
            _to,
            _value,
            _validAfter,
            _validBefore,
            _nonce
        );
        require(
            EIP712.recover(LibDiamond.domainSeparator(), _v, _r, _s, data) ==
                _from,
            "Invalid signature"
        );

        _markAuthorizationAsUsed(_from, _nonce);
        _transfer(_from, _to, _value);
    }

    function _receiveWithAuthorization(
        address _from,
        address _to,
        uint256 _value,
        uint256 _validAfter,
        uint256 _validBefore,
        bytes32 _nonce,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) internal {
        require(_to == msg.sender, "Caller must be the payee");
        _requireValidAuthorization(_from, _nonce, _validAfter, _validBefore);

        bytes memory data = abi.encode(
            _RECEIVE_WITH_AUTHORIZATION_TYPEHASH,
            _from,
            _to,
            _value,
            _validAfter,
            _validBefore,
            _nonce
        );
        require(
            EIP712.recover(LibDiamond.domainSeparator(), _v, _r, _s, data) ==
                _from,
            "Invalid signature"
        );

        _markAuthorizationAsUsed(_from, _nonce);
        _transfer(_from, _to, _value);
    }

    function _cancelAuthorization(
        address _authorizer,
        bytes32 _nonce,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) internal {
        _requireUnusedAuthorization(_authorizer, _nonce);

        bytes memory data = abi.encode(
            _CANCEL_AUTHORIZATION_TYPEHASH,
            _authorizer,
            _nonce
        );
        require(
            EIP712.recover(LibDiamond.domainSeparator(), _v, _r, _s, data) ==
                _authorizer,
            "Invalid signature"
        );

        _authorizationStates[_authorizer][_nonce] = true;
        emit AuthorizationCanceled(_authorizer, _nonce);
    }

    function _requireUnusedAuthorization(address _authorizer, bytes32 _nonce)
        private
        view
    {
        require(
            !_authorizationStates[_authorizer][_nonce],
            "Authorization is used or canceled"
        );
    }

    function _requireValidAuthorization(
        address _authorizer,
        bytes32 _nonce,
        uint256 _validAfter,
        uint256 _validBefore
    ) private view {
        require(
            block.timestamp > _validAfter,
            "Authorization is not yet valid"
        );
        require(block.timestamp < _validBefore, "Authorization is expired");
        _requireUnusedAuthorization(_authorizer, _nonce);
    }

    function _markAuthorizationAsUsed(address _authorizer, bytes32 _nonce)
        private
    {
        _authorizationStates[_authorizer][_nonce] = true;
        emit AuthorizationUsed(_authorizer, _nonce);
    }

    event RescuerChanged(address indexed _newRescuer);

    modifier onlyRescuer() {
        require(msg.sender == s.rescuer, "Caller is not the rescuer");
        _;
    }

    function rescueERC20(
        IERC20 _tokenContract,
        address _to,
        uint256 _amount
    ) external onlyRescuer {
        _tokenContract.safeTransfer(_to, _amount);
    }

    function updateRescuer(
        address _newRescuer,
        uint8[] memory _sigV,
        bytes32[] memory _sigR,
        bytes32[] memory _sigS
    ) external {
        require(_newRescuer != address(0), "New rescuer is the zero address");

        bytes memory data = abi.encode(
            /* keccak256("updateRescuer(address _newRescuer)") */
            0xd8c92999b7bb6daf516ed072fb0887e790e1faf54a95e77cd2932a318ebe01ee,
            _newRescuer,
            LibDiamond.configNonce()
        );

        LibDiamond.verifySignature(_sigV, _sigR, _sigS, data);

        s.rescuer = _newRescuer;
        emit RescuerChanged(s.rescuer);
    }

    event Pause();
    event Unpause();
    event PauserChanged(address indexed newAddress);

    modifier whenNotPaused() {
        require(!s.paused, "Paused");
        _;
    }

    modifier onlyPauser() {
        require(msg.sender == s.pauser, "Caller is not the pauser");
        _;
    }

    function pause() external onlyPauser {
        s.paused = true;
        emit Pause();
    }

    function unpause() external onlyPauser {
        s.paused = false;
        emit Unpause();
    }

    function updatePauser(
        address _newPauser,
        uint8[] memory _sigV,
        bytes32[] memory _sigR,
        bytes32[] memory _sigS
    ) external {
        require(_newPauser != address(0), "New pauser is the zero address");

        bytes memory data = abi.encode(
            /* keccak256("updatePauser(address _newPauser)") */
            0x9efeb16ed5a35ebbfc5ebafc3a7781b210708393cbbb88c85c54cf781016fcfe,
            _newPauser,
            LibDiamond.configNonce()
        );

        LibDiamond.verifySignature(_sigV, _sigR, _sigS, data);

        s.pauser = _newPauser;
        emit PauserChanged(s.pauser);
    }

    event Blacklisted(address indexed _account);
    event UnBlacklisted(address indexed _account);
    event BlacklisterChanged(address indexed _newBlacklister);

    modifier onlyBlacklister() {
        require(msg.sender == s.blacklister, "Caller is not the blacklister");
        _;
    }

    modifier notBlacklisted(address _account) {
        require(!s.blacklisted[_account], "Account is blacklisted");
        _;
    }

    function isBlacklisted(address _account) external view returns (bool) {
        return s.blacklisted[_account];
    }

    function blacklist(address _account) external onlyBlacklister {
        s.blacklisted[_account] = true;
        emit Blacklisted(_account);
    }

    function unBlacklist(address _account) external onlyBlacklister {
        s.blacklisted[_account] = false;
        emit UnBlacklisted(_account);
    }

    function updateBlacklister(
        address _newBlacklister,
        uint8[] memory _sigV,
        bytes32[] memory _sigR,
        bytes32[] memory _sigS
    ) external {
        require(
            _newBlacklister != address(0),
            "New blacklister is the zero address"
        );
        bytes memory data = abi.encode(
            0xb4fa77fa651e39fcdfff636505690262a48b1b6c279bd8571861fda1def16402,
            _newBlacklister,
            LibDiamond.configNonce()
        );

        LibDiamond.verifySignature(_sigV, _sigR, _sigS, data);
        s.blacklister = _newBlacklister;
        emit BlacklisterChanged(s.blacklister);
    }
}
