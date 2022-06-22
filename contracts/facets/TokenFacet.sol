// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IERC20} from "../interfaces/IERC20.sol";
import {IEIP3009} from "../interfaces/IEIP3009.sol";
import {IEIP2612} from "../interfaces/IEIP2612.sol";
import {SafeERC20} from "../libraries/SafeERC20.sol";
import {EIP712} from "../libraries/EIP712.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {AppStorage} from "../libraries/LibAppStorage.sol";

contract TokenFacet is IERC20, IEIP3009, IEIP2612 {
    AppStorage internal s;

    using SafeERC20 for IERC20;
    bool internal _initialized;

    event TokenSetup(
        address indexed initiator,
        string _name,
        string _version,
        string _token,
        uint8 decimals
    );
    event Mint(address indexed minter, address indexed to, uint256 amount);
    event Burn(address indexed burner, uint256 amount);
    event MinterConfigured(address indexed minter, uint256 minterAllowedAmount);
    event MinterRemoved(address indexed oldMinter);

    bytes32 internal _DOMAIN_SEPARATOR;

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

    function DOMAIN_SEPARATOR() external view returns (bytes32 ds_) {
        ds_ = _DOMAIN_SEPARATOR;
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

    /**
     * @dev Setup function sets initial storage of contract.
     * @param _name Name of token.
     * @param _symbol Token's symbol.
     * @param _decimals Decimals.
     */

    function setup(
        string memory _name,
        string memory _version,
        string memory _symbol,
        uint8 _decimals
    ) external {
        require(!_initialized);
        LibDiamond.enforceIsContractOwner();

        s.name = _name;
        s.version = _version;
        s.symbol = _symbol;
        s.decimals = _decimals;

        _DOMAIN_SEPARATOR = EIP712.makeDomainSeparator(_name, _version);
        _initialized = true;

        emit TokenSetup(msg.sender, _name, _version, _symbol, _decimals);
    }

    /**
     * @notice Version string for the EIP712 domain separator
     * @return version_ string
     */

    function version() external view returns (string memory version_) {
        version_ = s.version;
    }

    /**
     * @dev Throws if called by any account other than a minter
     */

    modifier onlyMinters() {
        require(s.minters[msg.sender], "Caller is not a minter");
        _;
    }

    /**
     * @dev Function to mint tokens
     * @param _to The address that will receive the minted tokens.
     * @param _amount The amount of tokens to mint. Must be less than or equal
     * to the minterAllowance of the caller.
     * @return A boolean that indicates if the operation was successful.
     */

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

    /**
     * @dev Get minter allowance for an account
     * @param _minter The address of the minter
     */

    function minterAllowance(address _minter)
        external
        view
        returns (uint256 amount_)
    {
        amount_ = s.minterAllowed[_minter];
    }

    /**
     * @dev Checks if account is a minter
     * @param _account The address _to check
     */

    function isMinter(address _account) external view returns (bool isMinter_) {
        isMinter_ = s.minters[_account];
    }

    /**
     * @notice Amount of remaining tokens spender is allowed to transfer on
     * behalf of the token owner
     * @param _owner     Token owner's address
     * @param _spender   Spender's address
     * @return amount_ Allowance amount
     */

    function allowance(address _owner, address _spender)
        external
        view
        returns (uint256 amount_)
    {
        amount_ = s.allowed[_owner][_spender];
    }

    /**
     * @dev Get totalSupply of token
     */

    function totalSupply() external view returns (uint256 amount_) {
        amount_ = s.totalSupply;
    }

    /**
     * @dev Get token balance of an account
     * @param _account address The account
     */

    function balanceOf(address _account)
        external
        view
        returns (uint256 amount_)
    {
        amount_ = s.balances[_account];
    }

    /**
     * @notice Set spender's allowance over the caller's tokens to be a given
     * value.
     * @param _spender   Spender's address
     * @param _value     Allowance amount
     * @return True if successful
     */

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

    /**
     * @dev Internal function to set allowance
     * @param _owner     Token owner's address
     * @param _spender   Spender's address
     * @param _value     Allowance amount
     */

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

    /**
     * @notice Transfer tokens by spending allowance
     * @param _from  Payer's address
     * @param _to    Payee's address
     * @param _value Transfer amount
     * @return True if successful
     */

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

    /**
     * @notice Transfer tokens from the caller
     * @param _to    Payee's address
     * @param _value Transfer amount
     */

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

    /**
     * @notice Internal function to process transfers
     * @param _from  Payer's address
     * @param _to    Payee's address
     * @param _value Transfer amount
     */
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

    /**
     * @dev Function to add/update a new minter
     * @param _minter The address of the minter
     * @param _minterAllowedAmount The minting amount allowed for the minter
     * @return True if the operation was successful.
     */

    function configureMinter(address _minter, uint256 _minterAllowedAmount)
        external
        whenNotPaused
        returns (bool)
    {
        LibDiamond.enforceIsContractOwner();

        s.minters[_minter] = true;
        s.minterAllowed[_minter] = _minterAllowedAmount;
        emit MinterConfigured(_minter, _minterAllowedAmount);
        return true;
    }

    /**
     * @dev Function to remove a minter
     * @param _minter The address of the minter to remove
     * @return True if the operation was successful.
     */

    function removeMinter(address _minter) external returns (bool) {
        LibDiamond.enforceIsContractOwner();

        s.minters[_minter] = false;
        s.minterAllowed[_minter] = 0;
        emit MinterRemoved(_minter);
        return true;
    }

    /**
     * @dev allows a minter to burn some of its own tokens
     * Validates that caller is a minter and that sender is not blacklisted
     * amount is less than or equal to the minter's account balance
     * @param _amount uint256 the amount of tokens to be burned
     */

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

    /**
     * @notice Increase the allowance by a given increment
     * @param _spender   Spender's address
     * @param _increment Amount of increase in allowance
     * @return True if successful
     */

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

    /**
     * @notice Decrease the allowance by a given decrement
     * @param _spender   Spender's address
     * @param _decrement Amount of decrease in allowance
     * @return True if successful
     */

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

    /**
     * @notice Execute a transfer with a signed authorization
     * @param _from          Payer's address (Authorizer)
     * @param _to            Payee's address
     * @param _value         Amount to be transferred
     * @param _validAfter    The time after which this is valid (unix time)
     * @param _validBefore   The time before which this is valid (unix time)
     * @param _nonce         Unique nonce
     * @param _v             v of the signature
     * @param _r             r of the signature
     * @param _s             s of the signature
     */

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

    /**
     * @notice Receive a transfer with a signed authorization from the payer
     * @dev This has an additional check to ensure that the payee's address
     * matches the caller of this function to prevent front-running attacks.
     * @param _from          Payer's address (Authorizer)
     * @param _to            Payee's address
     * @param _value         Amount to be transferred
     * @param _validAfter    The time after which this is valid (unix time)
     * @param _validBefore   The time before which this is valid (unix time)
     * @param _nonce         Unique nonce
     * @param _v             v of the signature
     * @param _r             r of the signature
     * @param _s             s of the signature
     */

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

    /**
     * @notice Attempt to cancel an authorization
     * @dev Works only if the authorization is not yet used.
     * @param _authorizer    Authorizer's address
     * @param _nonce         Nonce of the authorization
     * @param _v             v of the signature
     * @param _r             r of the signature
     * @param _s             s of the signature
     */

    function cancelAuthorization(
        address _authorizer,
        bytes32 _nonce,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external whenNotPaused {
        _cancelAuthorization(_authorizer, _nonce, _v, _r, _s);
    }

    /**
     * @notice Update allowance with a signed permit
     * @param _owner       Token owner's address (Authorizer)
     * @param _spender     Spender's address
     * @param _value       Amount of allowance
     * b@param _deadline    Expiration time, seconds since the epoch
     * @param _v           v of the signature
     * @param _r           r of the signature
     * @param _s           s of the signature
     */

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

    /**
     * @notice Internal function to increase the allowance by a given increment
     * @param _owner     Token owner's address
     * @param _spender   Spender's address
     * @param _increment Amount of increase
     */

    function _increaseAllowance(
        address _owner,
        address _spender,
        uint256 _increment
    ) internal {
        _approve(_owner, _spender, s.allowed[_owner][_spender] + _increment);
    }

    /**
     * @notice Internal function to decrease the allowance by a given decrement
     * @param _owner     Token owner's address
     * @param _spender   Spender's address
     * @param _decrement Amount of decrease
     */

    function _decreaseAllowance(
        address _owner,
        address _spender,
        uint256 _decrement
    ) internal {
        _approve(_owner, _spender, s.allowed[_owner][_spender] - _decrement);
    }

    /**
     * @notice Nonces for permit
     * @param _owner Token owner's address (Authorizer)
     * @return nonce_ Next nonce
     */

    function nonces(address _owner) external view returns (uint256 nonce_) {
        nonce_ = s.permitNonces[_owner];
    }

    /**
     * @notice EIP-2612 Verify a signed approval permit and execute if valid
     * @param _owner     Token owner's address (Authorizer)
     * @param _spender   Spender's address
     * @param _value     Amount of allowance
     * b@param _deadline  The time at which this expires (unix time)
     * @param _v         v of the signature
     * @param _r         r of the signature
     * @param _s         s of the signature
     */

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
            EIP712.recover(_DOMAIN_SEPARATOR, _v, _r, _s, data) == _owner,
            "Invalid signature"
        );

        _approve(_owner, _spender, _value);
    }

    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);

    /**
     * @notice Returns the state of an authorization
     * @dev Nonces are randomly generated 32-byte data unique to the
     * authorizer's address
     * @param _authorizer    Authorizer's address
     * @param _nonce         Nonce of the authorization
     * @return state_ True if the nonce is used
     */

    function authorizationState(address _authorizer, bytes32 _nonce)
        external
        view
        returns (bool state_)
    {
        state_ = s._authorizationStates[_authorizer][_nonce];
    }

    /**
     * @notice Execute a transfer with a signed authorization
     * @param _from          Payer's address (Authorizer)
     * @param _to            Payee's address
     * @param _value         Amount to be transferred
     * @param _validAfter    The time after which this is valid (unix time)
     * @param _validBefore   The time before which this is valid (unix time)
     * @param _nonce         Unique nonce
     * @param _v             v of the signature
     * @param _r             r of the signature
     * @param _s             s of the signature
     */

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
            EIP712.recover(_DOMAIN_SEPARATOR, _v, _r, _s, data) == _from,
            "Invalid signature"
        );

        _markAuthorizationAsUsed(_from, _nonce);
        _transfer(_from, _to, _value);
    }

    /**
     * @notice Receive a transfer with a signed authorization from the payer
     * @dev This has an additional check to ensure that the payee's address
     * matches the caller of this function to prevent front-running attacks.
     * @param _from          Payer's address (Authorizer)
     * @param _to            Payee's address
     * @param _value         Amount to be transferred
     * @param _validAfter    The time after which this is valid (unix time)
     * @param _validBefore   The time before which this is valid (unix time)
     * @param _nonce         Unique nonce
     * @param _v             v of the signature
     * @param _r             r of the signature
     * @param _s             s of the signature
     */

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
            EIP712.recover(_DOMAIN_SEPARATOR, _v, _r, _s, data) == _from,
            "Invalid signature"
        );

        _markAuthorizationAsUsed(_from, _nonce);
        _transfer(_from, _to, _value);
    }

    /**
     * @notice Attempt to cancel an authorization
     * @param _authorizer    Authorizer's address
     * @param _nonce         Nonce of the authorization
     * @param _v             v of the signature
     * @param _r             r of the signature
     * @param _s             s of the signature
     */

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
            EIP712.recover(_DOMAIN_SEPARATOR, _v, _r, _s, data) == _authorizer,
            "Invalid signature"
        );

        s._authorizationStates[_authorizer][_nonce] = true;
        emit AuthorizationCanceled(_authorizer, _nonce);
    }

    /**
     * @notice Check that an authorization is unused
     * @param _authorizer    Authorizer's address
     * @param _nonce         Nonce of the authorization
     */

    function _requireUnusedAuthorization(address _authorizer, bytes32 _nonce)
        private
        view
    {
        require(
            !s._authorizationStates[_authorizer][_nonce],
            "Authorization is used or canceled"
        );
    }

    /**
     * @notice Check that authorization is valid
     * @param _authorizer    Authorizer's address
     * @param _nonce         Nonce of the authorization
     * @param _validAfter    The time after which this is valid (unix time)
     * @param _validBefore   The time before which this is valid (unix time)
     */

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

    /**
     * @notice Mark an authorization as used
     * @param _authorizer    Authorizer's address
     * @param _nonce         Nonce of the authorization
     */

    function _markAuthorizationAsUsed(address _authorizer, bytes32 _nonce)
        private
    {
        s._authorizationStates[_authorizer][_nonce] = true;
        emit AuthorizationUsed(_authorizer, _nonce);
    }

    event RescuerChanged(address indexed _newRescuer);

    /**
     * @notice Revert if called by any account other than the rescuer.
     */

    modifier onlyRescuer() {
        require(msg.sender == s.rescuer, "Caller is not the rescuer");
        _;
    }

    /**
     * @notice Rescue ERC20 tokens locked up in this contract.
     * @param _tokenContract ERC20 token contract address
     * @param _to        Recipient address
     * @param _amount    Amount to withdraw
     */

    function rescueERC20(
        IERC20 _tokenContract,
        address _to,
        uint256 _amount
    ) external onlyRescuer {
        _tokenContract.safeTransfer(_to, _amount);
    }

    /**
     * @notice Assign the rescuer role to a given address.
     * @param _newRescuer New rescuer's address
     */

    function updateRescuer(address _newRescuer) external {
        require(_newRescuer != address(0), "New rescuer is the zero address");

        LibDiamond.enforceIsContractOwner();

        s.rescuer = _newRescuer;
        emit RescuerChanged(s.rescuer);
    }

    event Pause();
    event Unpause();
    event PauserChanged(address indexed newAddress);

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     */

    modifier whenNotPaused() {
        require(!s.paused, "Paused");
        _;
    }

    /**
     * @dev throws if called by any account other than the pauser
     */

    modifier onlyPauser() {
        require(msg.sender == s.pauser, "Caller is not the pauser");
        _;
    }

    /**
     * @dev called by the owner to pause, triggers stopped state
     */

    function pause() external onlyPauser {
        s.paused = true;
        emit Pause();
    }

    /**
     * @dev called by the owner to unpause, returns to normal state
     */

    function unpause() external onlyPauser {
        s.paused = false;
        emit Unpause();
    }

    /**
     * @notice Assign the pauser role to a given address.
     * @param _newPauser New pauser's address
     */

    function updatePauser(address _newPauser) external {
        require(_newPauser != address(0), "New pauser is the zero address");

        LibDiamond.enforceIsContractOwner();

        s.pauser = _newPauser;
        emit PauserChanged(s.pauser);
    }

    event Blacklisted(address indexed _account);
    event UnBlacklisted(address indexed _account);
    event BlacklisterChanged(address indexed _newBlacklister);

    /**
     * @dev Throws if called by any account other than the blacklister
     */

    modifier onlyBlacklister() {
        require(msg.sender == s.blacklister, "Caller is not the blacklister");
        _;
    }

    /**
     * @dev Throws if argument account is blacklisted
     * @param _account The address _to check
     */

    modifier notBlacklisted(address _account) {
        require(!s.blacklisted[_account], "Account is blacklisted");
        _;
    }

    /**
     * @dev Checks if account is blacklisted
     * @param _account The address _to check
     */

    function isBlacklisted(address _account) external view returns (bool) {
        return s.blacklisted[_account];
    }

    /**
     * @dev Adds account to blacklist
     * @param _account The address _to blacklist
     */

    function blacklist(address _account) external onlyBlacklister {
        s.blacklisted[_account] = true;
        emit Blacklisted(_account);
    }

    /**
     * @dev Removes account from blacklist
     * @param _account The address _to remove from the blacklist
     */

    function unBlacklist(address _account) external onlyBlacklister {
        s.blacklisted[_account] = false;
        emit UnBlacklisted(_account);
    }

    /**
     * @notice Assign the blacklister role to a given address.
     * @param _newBlacklister New blacklister's address
     */

    function updateBlacklister(address _newBlacklister) external {
        require(
            _newBlacklister != address(0),
            "New blacklister is the zero address"
        );

        LibDiamond.enforceIsContractOwner();

        s.blacklister = _newBlacklister;
        emit BlacklisterChanged(s.blacklister);
    }
}
