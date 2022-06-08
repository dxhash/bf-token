import sys
import time

import eth_abi
import pytest
from brownie import (
    Contract,
    Diamond,
    DiamondCutFacet,
    DiamondLoupeFacet,
    OwnershipFacet,
    TokenFacet,
    accounts,
    config,
    interface,
    network,
)
from eth_account import Account
from eth_account.messages import encode_defunct
from eth_typing import Primitives
from web3.auto import w3


# Is required to solve brownie reverts problem with Python >= 3.10
class reverts(object):
    def __init__(self, reason=""):
        self.reason = f" {reason}" if reason != "" else ""

    def __enter__(self):
        pass

    def __exit__(self, e_typ, e_val, trcbak):
        if e_typ is ValueError:
            return str(e_val).find(f"revert{self.reason}") >= 0

        elif e_typ is None:
            assert False, "Transaction did not revert"


def sign_digest(digest: str, key: str) -> set:
    message = encode_defunct(hexstr=digest).body
    res = Account._sign_hash(message, key)
    return (to_32byte_hex(res.r), to_32byte_hex(res.s), res.v)


def to_32byte_hex(val: Primitives) -> str:
    return w3.toHex(w3.toBytes(val).rjust(32, b"\0"))


@pytest.fixture
def global_var():

    # It has to be the same as the one that was used during deployment
    pytest.ACCOUNT_PRIVATE_KEY = config["networks"][network.show_active()]["from_key"]
    pytest.OTHER_ACCOUNT_PRIVATE_KEY = config["networks"][network.show_active()][
        "other_key"
    ]

    pytest.account = accounts.add(private_key=pytest.ACCOUNT_PRIVATE_KEY)
    pytest.other_account = accounts.add(private_key=pytest.OTHER_ACCOUNT_PRIVATE_KEY)

    pytest.DEPLOYED_NAME = config["token"]["name"]
    pytest.DEPLOYED_VERSION = config["token"]["version"]
    pytest.DEPLOYED_SYMBOL = config["token"]["symbol"]
    pytest.DEPLOYED_DECIMALS = config["token"]["decimals"]
    pytest.TEST_SUPPLY = 10 * 10**pytest.DEPLOYED_DECIMALS
    pytest.TEST_AMOUNT = 1 * 10**pytest.DEPLOYED_DECIMALS
    pytest.ZERO_ADDRESS = f"0x{'0' * 40}"

    pytest.PERMIT_TYPEHASH = (
        "0x283ef5f1323e8965c0333bc5843eb0b8d7ffe23b9c2eab15c3e3ffcc75ae8134"
    )
    pytest.TRANSFER_WITH_AUTHORIZATION_TYPEHASH = (
        "0x310777934f929c98189a844bb5f21f2844db2a576625365b824861540a319f79"
    )
    pytest.RECEIVE_WITH_AUTHORIZATION_TYPEHASH = (
        "0x58ac3df019d91fe0955489460a6a1c370bec91d993d7efbc0925fe3d403653eb"
    )
    pytest.CANCEL_AUTHORIZATION_TYPEHASH = (
        "0xf523c75f846f1f78c4e7be3cf73d7e9c0b2a8d15cd65153faae8afa14f91c341"
    )

    pytest.MAGIC_BYTES = w3.toBytes(hexstr="1901")

    pytest.diamond = Diamond[-1]
    pytest.token_facet = Contract.from_abi(
        "TokenFacet", pytest.diamond.address, abi=TokenFacet.abi
    )


@pytest.fixture
def global_var_and_domain_separator(global_var):

    # keccak256("EIP712Domain(string _name,string _version,uint256 _chainId,address _verifyingContract)")
    TYPE_HASH = "bc401e48a390421e8786d72c7fd44afeed5af1075ecfef31ed40894bdb0e96a5"

    pytest.DOMAIN_SEPARATOR = w3.keccak(
        hexstr=eth_abi.abi.encode_abi(
            [
                "bytes32",
                "bytes32",
                "bytes32",
                "uint256",
                "address",
            ],
            [
                w3.toBytes(hexstr=TYPE_HASH),
                w3.toBytes(hexstr=w3.keccak(text=pytest.DEPLOYED_NAME).hex()),
                w3.toBytes(hexstr=w3.keccak(text=pytest.DEPLOYED_VERSION).hex()),
                config["networks"][network.show_active()].get("chainid"),
                pytest.token_facet.address,
            ],
        ).hex()
    ).hex()


def test_001_deployment(global_var):

    """
    Functions:
        facetAddresses() external view override returns (address[] memory facetAddresses_);
        facetFunctionSelectors(address _facet);
        facetAddress(bytes4 _functionSelector) external view override returns (address facetAddress_);
    """

    diamond_loupe_facet = Contract.from_abi(
        "DiamondLoupeFacet", pytest.diamond.address, abi=DiamondLoupeFacet.abi
    )

    diamond_cut_facet = DiamondCutFacet[-1]
    ownership_facet = OwnershipFacet[-1]
    token_facet = TokenFacet[-1]

    facet_addresses = []

    # Should have 4 facets -- call to facetAddresses function
    for facet_address in diamond_loupe_facet.facetAddresses():
        facet_addresses.append(facet_address)

    assert len(facet_addresses) == 4

    # Facets should have the right function selectors -- call to facetFunctionSelectors function
    selectors = list(diamond_cut_facet.selectors.keys())
    assert set(
        [str(x) for x in diamond_loupe_facet.facetFunctionSelectors(facet_addresses[0])]
    ).issubset(set(selectors))

    selectors = list(diamond_loupe_facet.selectors.keys())
    assert set(
        [str(x) for x in diamond_loupe_facet.facetFunctionSelectors(facet_addresses[1])]
    ).issubset(set(selectors))

    selectors = list(ownership_facet.selectors.keys())
    assert set(
        [str(x) for x in diamond_loupe_facet.facetFunctionSelectors(facet_addresses[2])]
    ).issubset(set(selectors))

    selectors = list(token_facet.selectors.keys())
    assert set(
        [str(x) for x in diamond_loupe_facet.facetFunctionSelectors(facet_addresses[3])]
    ).issubset(set(selectors))

    # Selectors should be associated to facets correctly -- multiple calls to facetAddress function
    assert facet_addresses[0] == diamond_loupe_facet.facetAddress("0x1f931c1c")
    assert facet_addresses[1] == diamond_loupe_facet.facetAddress("0xcdffacc6")
    assert facet_addresses[2] == diamond_loupe_facet.facetAddress("0xf2fde38b")
    assert facet_addresses[3] == diamond_loupe_facet.facetAddress("0x7ecebe00")


def test_002_ownership_facet(global_var):

    """
    Functions:
        owner() external view override returns (address owner_);
        transferOwnership(address _newOwner) external override;
    """

    ownership_facet = Contract.from_abi(
        "OwnershipFacet", pytest.diamond.address, abi=OwnershipFacet.abi
    )

    current_owner = ownership_facet.owner()
    assert current_owner == pytest.account.address

    tx = ownership_facet.transferOwnership(
        pytest.other_account.address, {"from": pytest.account}
    )
    # tx = ownership_facet.transferOwnership(
    #    pytest.account.address, {"from": pytest.other_account}
    # )

    tx.wait(1)
    time.sleep(5)

    current_owner = ownership_facet.owner()
    assert current_owner == pytest.other_account.address

    tx = ownership_facet.transferOwnership(
        pytest.account.address, {"from": pytest.other_account}
    )
    tx.wait(1)
    time.sleep(5)

    current_owner = ownership_facet.owner()
    assert current_owner == pytest.account.address

    """
    All subsequent functions with notBlacklisted modifier must revert with `Must be contract owner` reason.
    (configureMinter, removeMinter, updateRescuer, updatePauser, updateBlacklister)
    """

    with reverts("Must be contract owner"):
        pytest.token_facet.configureMinter(
            pytest.other_account, 0, {"from": pytest.other_account}
        )
        pytest.token_facet.removeMinter(
            pytest.other_account, {"from": pytest.other_account}
        )
        pytest.token_facet.updateRescuer(
            pytest.other_account, {"from": pytest.other_account}
        )
        pytest.token_facet.updatePauser(
            pytest.other_account, {"from": pytest.other_account}
        )
        pytest.token_facet.updateBlacklister(
            pytest.other_account, {"from": pytest.other_account}
        )


def test_003_token_facet_setup(global_var):

    """
    Functions:
        setup(string memory _name, string memory _symbol, uint8 _decimals) external;
    """

    with reverts():
        pytest.token_facet.setup(
            pytest.DEPLOYED_NAME,
            pytest.DEPLOYED_VERSION,
            pytest.DEPLOYED_SYMBOL,
            pytest.DEPLOYED_DECIMALS,
            {"from": pytest.account},
        )


def test_004_token_facet_appstorage(global_var):

    """
    Functions:
        name() external view returns (string memory name_);
        symbol() external view returns (string memory symbol_);
        decimals() external view returns (uint8 decimals_);
    """

    assert pytest.token_facet.name() == pytest.DEPLOYED_NAME
    assert pytest.token_facet.version() == pytest.DEPLOYED_VERSION
    assert pytest.token_facet.symbol() == pytest.DEPLOYED_SYMBOL
    assert pytest.token_facet.decimals() == pytest.DEPLOYED_DECIMALS


def test_005_token_facet_mint_burn(global_var):

    """
    Functions:
        mint(address _to, uint256 _amount);
        burn(uint256 _amount);
        minterAllowance(address _minter);
        isMinter(address _account) external view returns (bool isMinter_);
        totalSupply() external view returns (uint256 amount_);
        balanceOf(address _account);
        configureMinter(address _minter, uint256 _minterAllowedAmount);
        removeMinter(address _minter) external returns (bool);

    """

    pre_mint_total_supply = pytest.token_facet.totalSupply()
    pre_mint_balance = pytest.token_facet.balanceOf(pytest.account.address)

    expected_total_supply = pre_mint_total_supply + pytest.TEST_SUPPLY
    expected_balance = pre_mint_balance + pytest.TEST_SUPPLY

    is_minter = pytest.token_facet.isMinter(pytest.account.address)

    if is_minter == False:
        tx = pytest.token_facet.configureMinter(
            pytest.account.address, pytest.TEST_SUPPLY, {"from": pytest.account}
        )
        tx.wait(1)
        time.sleep(5)

    elif is_minter == True:
        minter_allowance = pytest.token_facet.minterAllowance(pytest.account.address)

        if minter_allowance < pytest.TEST_SUPPLY:

            tx = pytest.token_facet.configureMinter(
                pytest.account.address,
                pytest.TEST_SUPPLY - minter_allowance,
                {"from": pytest.account},
            )
            tx.wait(1)
            time.sleep(5)

    post_config_minter_allowance = pytest.token_facet.minterAllowance(
        pytest.account.address
    )

    assert pytest.token_facet.isMinter(pytest.account.address) == True
    assert post_config_minter_allowance == pytest.TEST_SUPPLY

    with reverts("Mint to the zero address"):
        pytest.token_facet.mint(
            pytest.ZERO_ADDRESS, pytest.TEST_SUPPLY, {"from": pytest.account}
        )

    with reverts("Mint amount not greater than 0"):
        pytest.token_facet.mint(pytest.account.address, 0, {"from": pytest.account})

    with reverts("Mint amount exceeds minterAllowance"):
        pytest.token_facet.mint(
            pytest.account.address, pytest.TEST_SUPPLY + 1, {"from": pytest.account}
        )

    tx = pytest.token_facet.mint(
        pytest.account.address, pytest.TEST_SUPPLY, {"from": pytest.account}
    )
    tx.wait(1)
    time.sleep(5)

    post_mint_total_supply = pytest.token_facet.totalSupply()
    post_mint_balance = pytest.token_facet.balanceOf(pytest.account.address)

    assert post_mint_total_supply == expected_total_supply
    assert post_mint_balance == expected_balance

    pre_burn_total_supply = pytest.token_facet.totalSupply()
    pre_burn_balance = pytest.token_facet.balanceOf(pytest.account.address)

    expected_total_supply = pre_burn_total_supply - pytest.TEST_AMOUNT
    expected_balance = pre_burn_balance - pytest.TEST_AMOUNT

    with reverts("Burn amount not greater than 0"):
        pytest.token_facet.burn(0, {"from": pytest.account})

    with reverts("Burn amount exceeds balance"):
        pytest.token_facet.burn(pytest.TEST_SUPPLY + 1, {"from": pytest.account})

    tx = pytest.token_facet.burn(pytest.TEST_AMOUNT, {"from": pytest.account})
    tx.wait(1)
    time.sleep(5)

    post_burn_total_supply = pytest.token_facet.totalSupply()
    post_burn_balance = pytest.token_facet.balanceOf(pytest.account.address)

    assert post_burn_total_supply == expected_total_supply
    assert post_burn_balance == expected_balance

    tx = pytest.token_facet.removeMinter(
        pytest.account.address, {"from": pytest.account}
    )
    tx.wait(1)
    time.sleep(5)

    assert pytest.token_facet.isMinter(pytest.account.address) == False


def test_006_token_facet_transfer(global_var):

    """
    Functions:
        transfer(address _to, uint256 _value);
        approve(address _spender, uint256 _value);
        transferFrom(address _from, address _to, uint256 _value) external returns (bool);
    """

    pre_transfer_balance_from = pytest.token_facet.balanceOf(pytest.account.address)
    pre_transfer_balance_to = pytest.token_facet.balanceOf(pytest.other_account.address)

    expected_balance_from = pre_transfer_balance_from - pytest.TEST_AMOUNT
    expected_balance_to = pre_transfer_balance_to + pytest.TEST_AMOUNT

    with reverts("Transfer to the zero address"):
        pytest.token_facet.transfer(
            pytest.ZERO_ADDRESS, pytest.TEST_AMOUNT, {"from": pytest.account}
        )

    with reverts("Transfer amount exceeds balance"):
        pytest.token_facet.transfer(
            pytest.other_account.address,
            pytest.TEST_SUPPLY + 1,
            {"from": pytest.account},
        )

    tx = pytest.token_facet.transfer(
        pytest.other_account.address, pytest.TEST_AMOUNT, {"from": pytest.account}
    )
    tx.wait(1)
    time.sleep(5)

    post_transfer_balance_from = pytest.token_facet.balanceOf(pytest.account.address)
    post_transfer_balance_to = pytest.token_facet.balanceOf(
        pytest.other_account.address
    )

    assert post_transfer_balance_from == expected_balance_from
    assert post_transfer_balance_to == expected_balance_to

    pre_transfer_balance_from = post_transfer_balance_from
    pre_transfer_balance_to = post_transfer_balance_to

    expected_balance_from = pre_transfer_balance_from - pytest.TEST_AMOUNT
    expected_balance_to = pre_transfer_balance_to + pytest.TEST_AMOUNT

    with reverts("Approve to the zero address"):
        pytest.token_facet.approve(
            pytest.ZERO_ADDRESS, pytest.TEST_AMOUNT, {"from": pytest.account}
        )

    tx = pytest.token_facet.approve(
        pytest.other_account.address, pytest.TEST_AMOUNT, {"from": pytest.account}
    )
    tx.wait(1)
    time.sleep(5)

    with reverts("Transfer amount exceeds allowance"):
        pytest.token_facet.transferFrom(
            pytest.account.address,
            pytest.other_account.address,
            pytest.TEST_AMOUNT + 1,
            {"from": pytest.other_account},
        )

    tx = pytest.token_facet.transferFrom(
        pytest.account.address,
        pytest.other_account.address,
        pytest.TEST_AMOUNT,
        {"from": pytest.other_account},
    )

    tx.wait(1)
    time.sleep(5)

    post_transfer_balance_from = pytest.token_facet.balanceOf(pytest.account.address)
    post_transfer_balance_to = pytest.token_facet.balanceOf(
        pytest.other_account.address
    )

    assert post_transfer_balance_from == expected_balance_from
    assert post_transfer_balance_to == expected_balance_to


def test_007_token_facet_allowance(global_var):

    """
    Functions:
        allowance(address _owner, address _spender);
        increaseAllowance(address _spender, uint256 _increment);
        decreaseAllowance(address _spender, uint256 _decrement);
    """

    pre_inc_allowance = pytest.token_facet.allowance(
        pytest.account.address, pytest.other_account.address
    )

    tx = pytest.token_facet.increaseAllowance(
        pytest.other_account.address,
        pytest.TEST_AMOUNT,
        {"from": pytest.account},
    )

    tx.wait(1)
    time.sleep(5)

    post_inc_allowance = pytest.token_facet.allowance(
        pytest.account.address, pytest.other_account.address
    )

    assert post_inc_allowance == pre_inc_allowance + pytest.TEST_AMOUNT

    pre_transfer_balance_from = pytest.token_facet.balanceOf(pytest.account.address)
    pre_transfer_balance_to = pytest.token_facet.balanceOf(pytest.other_account.address)

    expected_balance_from = pre_transfer_balance_from - pytest.TEST_AMOUNT
    expected_balance_to = pre_transfer_balance_to + pytest.TEST_AMOUNT

    tx = pytest.token_facet.transferFrom(
        pytest.account.address,
        pytest.other_account.address,
        pytest.TEST_AMOUNT,
        {"from": pytest.other_account},
    )

    tx.wait(1)
    time.sleep(5)

    post_transfer_allowance = pytest.token_facet.allowance(
        pytest.account.address, pytest.other_account.address
    )

    assert post_transfer_allowance == pre_inc_allowance

    post_transfer_balance_from = pytest.token_facet.balanceOf(pytest.account.address)
    post_transfer_balance_to = pytest.token_facet.balanceOf(
        pytest.other_account.address
    )

    assert post_transfer_balance_from == expected_balance_from
    assert post_transfer_balance_to == expected_balance_to

    tx = pytest.token_facet.increaseAllowance(
        pytest.other_account.address,
        pytest.TEST_AMOUNT,
        {"from": pytest.account},
    )

    tx.wait(1)
    time.sleep(5)

    tx = pytest.token_facet.decreaseAllowance(
        pytest.other_account.address,
        pytest.TEST_AMOUNT,
        {"from": pytest.account},
    )

    tx.wait(1)
    time.sleep(5)

    post_decrease_allowance = pytest.token_facet.allowance(
        pytest.account.address, pytest.other_account.address
    )

    assert post_decrease_allowance == pre_inc_allowance


def test_008_token_facet_eip2612(global_var_and_domain_separator):

    """
    Functions:
        DOMAIN_SEPARATOR() external pure returns (bytes32 ds_);
        PERMIT_TYPEHASH() external pure returns (bytes32 pth_);
        permit(
            address _owner,
            address _spender,
            uint256 _value,
            uint256 _deadline,
            uint8 _v,
            bytes32 _r,
            bytes32 _s
        ) external;
    """

    assert pytest.token_facet.DOMAIN_SEPARATOR() == pytest.DOMAIN_SEPARATOR
    assert pytest.token_facet.PERMIT_TYPEHASH() == pytest.PERMIT_TYPEHASH

    pre_permit_nonce = pytest.token_facet.nonces(pytest.account.address)
    deadline = sys.maxsize

    digest = w3.keccak(
        hexstr=(
            pytest.MAGIC_BYTES
            + w3.toBytes(hexstr=pytest.DOMAIN_SEPARATOR)
            + w3.keccak(
                hexstr=eth_abi.abi.encode_abi(
                    [
                        "bytes32",
                        "address",
                        "address",
                        "uint256",
                        "uint256",
                        "uint256",
                    ],
                    [
                        w3.toBytes(hexstr=pytest.PERMIT_TYPEHASH),
                        pytest.account.address,
                        pytest.other_account.address,
                        pytest.TEST_AMOUNT,
                        pre_permit_nonce,
                        deadline,
                    ],
                ).hex()
            )
        ).hex()
    ).hex()

    signed_message_r, signed_message_s, signed_message_v = sign_digest(
        digest, pytest.ACCOUNT_PRIVATE_KEY
    )

    with reverts("Permit is expired"):
        pytest.token_facet.permit(
            pytest.account.address,
            pytest.other_account.address,
            pytest.TEST_AMOUNT,
            0,
            signed_message_v,
            signed_message_r,
            signed_message_s,
            {"from": pytest.other_account},
        )

    with reverts("Invalid signature"):
        pytest.token_facet.permit(
            pytest.account.address,
            pytest.other_account.address,
            pytest.TEST_AMOUNT,
            deadline,
            0,
            signed_message_r,
            signed_message_s,
            {"from": pytest.other_account},
        )

    tx = pytest.token_facet.permit(
        pytest.account.address,
        pytest.other_account.address,
        pytest.TEST_AMOUNT,
        deadline,
        signed_message_v,
        signed_message_r,
        signed_message_s,
        {"from": pytest.other_account},
    )

    tx.wait(1)
    time.sleep(5)

    post_permit_nonce = pytest.token_facet.nonces(pytest.account.address)

    assert post_permit_nonce > pre_permit_nonce

    pre_transfer_balance_from = pytest.token_facet.balanceOf(pytest.account.address)
    pre_transfer_balance_to = pytest.token_facet.balanceOf(pytest.other_account.address)

    expected_balance_from = pre_transfer_balance_from - pytest.TEST_AMOUNT
    expected_balance_to = pre_transfer_balance_to + pytest.TEST_AMOUNT

    tx = pytest.token_facet.approve(
        pytest.other_account.address, pytest.TEST_AMOUNT, {"from": pytest.account}
    )
    tx.wait(1)
    time.sleep(5)

    tx = pytest.token_facet.transferFrom(
        pytest.account.address,
        pytest.other_account.address,
        pytest.TEST_AMOUNT,
        {"from": pytest.other_account},
    )

    tx.wait(1)
    time.sleep(5)

    post_transfer_balance_from = pytest.token_facet.balanceOf(pytest.account.address)
    post_transfer_balance_to = pytest.token_facet.balanceOf(
        pytest.other_account.address
    )

    assert post_transfer_balance_from == expected_balance_from
    assert post_transfer_balance_to == expected_balance_to


def test_009_token_facet_eip3009(global_var_and_domain_separator):

    """

    Functions:
        TRANSFER_WITH_AUTHORIZATION_TYPEHASH();
        RECEIVE_WITH_AUTHORIZATION_TYPEHASH();
        CANCEL_AUTHORIZATION_TYPEHASH();

        transferWithAuthorization(
            address _from,
            address _to,
            uint256 _value,
            uint256 _validAfter,
            uint256 _validBefore,
            bytes32 _nonce,
            uint8 _v,
            bytes32 _r,
            bytes32 _s
        ) external;

        receiveWithAuthorization(
            address _from,
            address _to,
            uint256 _value,
            uint256 _validAfter,
            uint256 _validBefore,
            bytes32 _nonce,
            uint8 _v,
            bytes32 _r,
            bytes32 _s
        ) external;

        cancelAuthorization(
            address _authorizer,
            bytes32 _nonce,
            uint8 _v,
            bytes32 _r,
            bytes32 _s
        ) external;

        authorizationState(
            address _authorizer,
            bytes32 _nonce
        ) external view returns (bool state_);
    """

    assert pytest.token_facet.DOMAIN_SEPARATOR() == pytest.DOMAIN_SEPARATOR
    assert pytest.token_facet.PERMIT_TYPEHASH() == pytest.PERMIT_TYPEHASH

    assert (
        pytest.token_facet.TRANSFER_WITH_AUTHORIZATION_TYPEHASH()
        == pytest.TRANSFER_WITH_AUTHORIZATION_TYPEHASH
    )
    assert (
        pytest.token_facet.RECEIVE_WITH_AUTHORIZATION_TYPEHASH()
        == pytest.RECEIVE_WITH_AUTHORIZATION_TYPEHASH
    )
    assert (
        pytest.token_facet.CANCEL_AUTHORIZATION_TYPEHASH()
        == pytest.CANCEL_AUTHORIZATION_TYPEHASH
    )

    nonce = to_32byte_hex(int(time.time() * 1000))
    valid_after = int(time.time()) - 600
    valid_before = int(time.time()) + 600

    digest = w3.keccak(
        hexstr=(
            pytest.MAGIC_BYTES
            + w3.toBytes(hexstr=pytest.DOMAIN_SEPARATOR)
            + w3.keccak(
                hexstr=eth_abi.abi.encode_abi(
                    [
                        "bytes32",
                        "address",
                        "address",
                        "uint256",
                        "uint256",
                        "uint256",
                        "bytes32",
                    ],
                    [
                        w3.toBytes(hexstr=pytest.TRANSFER_WITH_AUTHORIZATION_TYPEHASH),
                        pytest.account.address,
                        pytest.other_account.address,
                        pytest.TEST_AMOUNT,
                        valid_after,
                        valid_before,
                        w3.toBytes(hexstr=nonce),
                    ],
                ).hex()
            )
        ).hex()
    ).hex()

    signed_message_r, signed_message_s, signed_message_v = sign_digest(
        digest, pytest.ACCOUNT_PRIVATE_KEY
    )

    pre_transfer_balance_from = pytest.token_facet.balanceOf(pytest.account.address)
    pre_transfer_balance_to = pytest.token_facet.balanceOf(pytest.other_account.address)

    expected_balance_from = pre_transfer_balance_from - pytest.TEST_AMOUNT
    expected_balance_to = pre_transfer_balance_to + pytest.TEST_AMOUNT

    with reverts("Authorization is not yet valid"):
        tx = pytest.token_facet.transferWithAuthorization(
            pytest.account.address,
            pytest.other_account.address,
            pytest.TEST_AMOUNT,
            valid_before,
            valid_before,
            nonce,
            signed_message_v,
            signed_message_r,
            signed_message_s,
            {"from": pytest.other_account},
        )

    with reverts("Authorization is expired"):
        tx = pytest.token_facet.transferWithAuthorization(
            pytest.account.address,
            pytest.other_account.address,
            pytest.TEST_AMOUNT,
            valid_after,
            valid_after,
            nonce,
            signed_message_v,
            signed_message_r,
            signed_message_s,
            {"from": pytest.other_account},
        )

    with reverts("Invalid signature"):
        tx = pytest.token_facet.transferWithAuthorization(
            pytest.account.address,
            pytest.other_account.address,
            pytest.TEST_AMOUNT + 1,
            valid_after,
            valid_before,
            nonce,
            signed_message_v,
            signed_message_r,
            signed_message_s,
            {"from": pytest.other_account},
        )

    tx = pytest.token_facet.transferWithAuthorization(
        pytest.account.address,
        pytest.other_account.address,
        pytest.TEST_AMOUNT,
        valid_after,
        valid_before,
        nonce,
        signed_message_v,
        signed_message_r,
        signed_message_s,
        {"from": pytest.other_account},
    )

    tx.wait(1)
    time.sleep(5)

    post_transfer_balance_from = pytest.token_facet.balanceOf(pytest.account.address)
    post_transfer_balance_to = pytest.token_facet.balanceOf(
        pytest.other_account.address
    )

    assert post_transfer_balance_from == expected_balance_from
    assert post_transfer_balance_to == expected_balance_to

    nonce = to_32byte_hex(int(time.time() * 1000))
    valid_after = int(time.time()) - 600
    valid_before = int(time.time()) + 600

    digest = w3.keccak(
        hexstr=(
            pytest.MAGIC_BYTES
            + w3.toBytes(hexstr=pytest.DOMAIN_SEPARATOR)
            + w3.keccak(
                hexstr=eth_abi.abi.encode_abi(
                    [
                        "bytes32",
                        "address",
                        "address",
                        "uint256",
                        "uint256",
                        "uint256",
                        "bytes32",
                    ],
                    [
                        w3.toBytes(hexstr=pytest.RECEIVE_WITH_AUTHORIZATION_TYPEHASH),
                        pytest.account.address,
                        pytest.other_account.address,
                        pytest.TEST_AMOUNT,
                        valid_after,
                        valid_before,
                        w3.toBytes(hexstr=nonce),
                    ],
                ).hex()
            )
        ).hex()
    ).hex()

    signed_message_r, signed_message_s, signed_message_v = sign_digest(
        digest, pytest.ACCOUNT_PRIVATE_KEY
    )

    pre_transfer_balance_from = pytest.token_facet.balanceOf(pytest.account.address)
    pre_transfer_balance_to = pytest.token_facet.balanceOf(pytest.other_account.address)

    expected_balance_from = pre_transfer_balance_from - pytest.TEST_AMOUNT
    expected_balance_to = pre_transfer_balance_to + pytest.TEST_AMOUNT

    with reverts("Authorization is not yet valid"):
        tx = pytest.token_facet.receiveWithAuthorization(
            pytest.account.address,
            pytest.other_account.address,
            pytest.TEST_AMOUNT,
            valid_before,
            valid_before,
            nonce,
            signed_message_v,
            signed_message_r,
            signed_message_s,
            {"from": pytest.other_account},
        )

    with reverts("Authorization is expired"):
        tx = pytest.token_facet.receiveWithAuthorization(
            pytest.account.address,
            pytest.other_account.address,
            pytest.TEST_AMOUNT,
            valid_after,
            valid_after,
            nonce,
            signed_message_v,
            signed_message_r,
            signed_message_s,
            {"from": pytest.other_account},
        )

    with reverts("Caller must be the payee"):
        tx = pytest.token_facet.receiveWithAuthorization(
            pytest.account.address,
            pytest.other_account.address,
            pytest.TEST_AMOUNT,
            valid_after,
            valid_after,
            nonce,
            signed_message_v,
            signed_message_r,
            signed_message_s,
            {"from": pytest.account},
        )

    tx = pytest.token_facet.receiveWithAuthorization(
        pytest.account.address,
        pytest.other_account.address,
        pytest.TEST_AMOUNT,
        valid_after,
        valid_before,
        nonce,
        signed_message_v,
        signed_message_r,
        signed_message_s,
        {"from": pytest.other_account},
    )

    tx.wait(1)
    time.sleep(5)

    post_transfer_balance_from = pytest.token_facet.balanceOf(pytest.account.address)
    post_transfer_balance_to = pytest.token_facet.balanceOf(
        pytest.other_account.address
    )

    assert post_transfer_balance_from == expected_balance_from
    assert post_transfer_balance_to == expected_balance_to

    nonce = to_32byte_hex(int(time.time() * 1000))
    valid_after = int(time.time()) - 600
    valid_before = int(time.time()) + 600

    digest = w3.keccak(
        hexstr=(
            pytest.MAGIC_BYTES
            + w3.toBytes(hexstr=pytest.DOMAIN_SEPARATOR)
            + w3.keccak(
                hexstr=eth_abi.abi.encode_abi(
                    [
                        "bytes32",
                        "address",
                        "address",
                        "uint256",
                        "uint256",
                        "uint256",
                        "bytes32",
                    ],
                    [
                        w3.toBytes(hexstr=pytest.RECEIVE_WITH_AUTHORIZATION_TYPEHASH),
                        pytest.account.address,
                        pytest.other_account.address,
                        pytest.TEST_AMOUNT,
                        valid_after,
                        valid_before,
                        w3.toBytes(hexstr=nonce),
                    ],
                ).hex()
            )
        ).hex()
    ).hex()

    signed_message_r, signed_message_s, signed_message_v = sign_digest(
        digest, pytest.ACCOUNT_PRIVATE_KEY
    )

    with reverts("Invalid signature"):
        tx = pytest.token_facet.receiveWithAuthorization(
            pytest.account.address,
            pytest.other_account.address,
            pytest.TEST_AMOUNT + 1,
            valid_after,
            valid_before,
            nonce,
            signed_message_v,
            signed_message_r,
            signed_message_s,
            {"from": pytest.other_account},
        )

        tx.wait(1)
        time.sleep(5)

    assert pytest.token_facet.authorizationState(pytest.account.address, nonce) == False

    digest = w3.keccak(
        hexstr=(
            pytest.MAGIC_BYTES
            + w3.toBytes(hexstr=pytest.DOMAIN_SEPARATOR)
            + w3.keccak(
                hexstr=eth_abi.abi.encode_abi(
                    ["bytes32", "address", "bytes32"],
                    [
                        w3.toBytes(hexstr=pytest.CANCEL_AUTHORIZATION_TYPEHASH),
                        pytest.account.address,
                        w3.toBytes(hexstr=nonce),
                    ],
                ).hex()
            )
        ).hex()
    ).hex()

    signed_message_r, signed_message_s, signed_message_v = sign_digest(
        digest, pytest.ACCOUNT_PRIVATE_KEY
    )

    tx = pytest.token_facet.cancelAuthorization(
        pytest.account.address,
        nonce,
        signed_message_v,
        signed_message_r,
        signed_message_s,
        {"from": pytest.other_account},
    )

    tx.wait(1)
    time.sleep(5)

    assert pytest.token_facet.authorizationState(pytest.account.address, nonce) == True


def test_010_token_facet_pausable(global_var):
    """
    Functions:
        pause() external;
        unpause() external;
        updatePauser(address _newPauser) external;

    """
    with reverts("Caller is not the pauser"):
        tx = pytest.token_facet.pause(
            {"from": pytest.account},
        )

    tx = pytest.token_facet.updatePauser(
        pytest.account.address,
        {"from": pytest.account},
    )

    tx.wait(1)
    time.sleep(5)

    tx = pytest.token_facet.pause(
        {"from": pytest.account},
    )

    tx.wait(1)
    time.sleep(5)

    """
    All subsequent functions with whenNotPaused modifier must be reverted with `Paused` reason.
    (transferFrom, transfer, configureMinter, mint, burn, approve, permit,
    increaseAllowance, decreaseAllowance, transferWithAuthorization,
    receiveWithAuthorization, cancelAuthorization)
    """

    with reverts("Paused"):
        pytest.token_facet.transferFrom(
            pytest.ZERO_ADDRESS,
            pytest.ZERO_ADDRESS,
            0,
            {"from": pytest.account},
        )
        pytest.token_facet.transfer(
            pytest.ZERO_ADDRESS,
            pytest.ZERO_ADDRESS,
            0,
            {"from": pytest.account},
        )
        pytest.token_facet.configureMinter(
            pytest.ZERO_ADDRESS,
            0,
            {"from": pytest.account},
        )
        pytest.token_facet.mint(
            pytest.ZERO_ADDRESS,
            0,
            {"from": pytest.account},
        )
        pytest.token_facet.burn(
            0,
            {"from": pytest.account},
        )
        pytest.token_facet.approve(
            pytest.ZERO_ADDRESS,
            0,
            {"from": pytest.account},
        )
        pytest.token_facet.permit(
            pytest.ZERO_ADDRESS,
            pytest.ZERO_ADDRESS,
            0,
            0,
            0,
            w3.toBytes(hexstr="00"),
            w3.toBytes(hexstr="00"),
            {"from": pytest.account},
        )
        pytest.token_facet.increaseAllowance(
            pytest.ZERO_ADDRESS,
            0,
            {"from": pytest.account},
        )
        pytest.token_facet.decreaseAllowance(
            pytest.ZERO_ADDRESS,
            0,
            {"from": pytest.account},
        )
        pytest.token_facet.transferWithAuthorization(
            pytest.ZERO_ADDRESS,
            pytest.ZERO_ADDRESS,
            0,
            0,
            0,
            w3.toBytes(hexstr="00"),
            0,
            w3.toBytes(hexstr="00"),
            w3.toBytes(hexstr="00"),
            {"from": pytest.account},
        )
        pytest.token_facet.receiveWithAuthorization(
            pytest.ZERO_ADDRESS,
            pytest.ZERO_ADDRESS,
            0,
            0,
            0,
            w3.toBytes(hexstr="00"),
            0,
            w3.toBytes(hexstr="00"),
            w3.toBytes(hexstr="00"),
            {"from": pytest.account},
        )
        pytest.token_facet.cancelAuthorization(
            w3.toBytes(hexstr="00"),
            0,
            w3.toBytes(hexstr="00"),
            w3.toBytes(hexstr="00"),
            {"from": pytest.account},
        )

    tx = pytest.token_facet.unpause(
        {"from": pytest.account},
    )

    tx.wait(1)
    time.sleep(5)

    tx = pytest.token_facet.updatePauser(
        pytest.other_account.address,
        {"from": pytest.account},
    )

    tx.wait(1)
    time.sleep(5)


def test_011_token_facet_blacklistable(global_var):
    """
    Functions:
        isBlacklisted(address _account) external view returns (bool);
        blacklist(address _account) external;
        unBlacklist(address _account) external;
        updateBlacklister(address _newBlacklister) external;

    """

    is_blacklisted = pytest.token_facet.isBlacklisted(pytest.other_account.address)
    assert is_blacklisted == False

    with reverts("Caller is not the blacklister"):
        pytest.token_facet.blacklist(
            pytest.other_account.address, {"from": pytest.account}
        )

    tx = pytest.token_facet.updateBlacklister(
        pytest.account.address, {"from": pytest.account}
    )
    tx.wait(1)
    time.sleep(5)

    tx = pytest.token_facet.blacklist(
        pytest.other_account.address, {"from": pytest.account}
    )
    tx.wait(1)
    time.sleep(5)

    """
    All subsequent functions with notBlacklisted modifier must revert with `Account is blacklisted` reason.
    (transferFrom, transfer, configureMinter, mint, burn, approve, permit,
    increaseAllowance, decreaseAllowance, transferWithAuthorization,
    receiveWithAuthorization)
    """

    with reverts("Account is blacklisted"):
        pytest.token_facet.transferFrom(
            pytest.other_account.address,
            pytest.ZERO_ADDRESS,
            0,
            {"from": pytest.account},
        )
        pytest.token_facet.transferFrom(
            pytest.ZERO_ADDRESS,
            pytest.other_account.address,
            0,
            {"from": pytest.account},
        )
        pytest.token_facet.transfer(
            pytest.other_account.address,
            pytest.ZERO_ADDRESS,
            0,
            {"from": pytest.account},
        )
        pytest.token_facet.transfer(
            pytest.ZERO_ADDRESS,
            pytest.other_account.address,
            0,
            {"from": pytest.account},
        )
        pytest.token_facet.configureMinter(
            pytest.other_account.address,
            0,
            {"from": pytest.account},
        )
        pytest.token_facet.mint(
            pytest.other_account.address,
            0,
            {"from": pytest.account},
        )
        pytest.token_facet.approve(
            pytest.other_account.address,
            0,
            {"from": pytest.account},
        )
        pytest.token_facet.permit(
            pytest.other_account.address,
            pytest.ZERO_ADDRESS,
            0,
            0,
            0,
            w3.toBytes(hexstr="00"),
            w3.toBytes(hexstr="00"),
            {"from": pytest.account},
        )
        pytest.token_facet.permit(
            pytest.ZERO_ADDRESS,
            pytest.other_account.address,
            0,
            0,
            0,
            w3.toBytes(hexstr="00"),
            w3.toBytes(hexstr="00"),
            {"from": pytest.account},
        )

        pytest.token_facet.increaseAllowance(
            pytest.other_account.address,
            0,
            {"from": pytest.account},
        )
        pytest.token_facet.decreaseAllowance(
            pytest.other_account.address,
            0,
            {"from": pytest.account},
        )
        pytest.token_facet.transferWithAuthorization(
            pytest.other_account.address,
            pytest.ZERO_ADDRESS,
            0,
            0,
            0,
            w3.toBytes(hexstr="00"),
            0,
            w3.toBytes(hexstr="00"),
            w3.toBytes(hexstr="00"),
            {"from": pytest.account},
        )
        pytest.token_facet.transferWithAuthorization(
            pytest.ZERO_ADDRESS,
            pytest.other_account.address,
            0,
            0,
            0,
            w3.toBytes(hexstr="00"),
            0,
            w3.toBytes(hexstr="00"),
            w3.toBytes(hexstr="00"),
            {"from": pytest.account},
        )
        pytest.token_facet.receiveWithAuthorization(
            pytest.other_account.address,
            pytest.ZERO_ADDRESS,
            0,
            0,
            0,
            w3.toBytes(hexstr="00"),
            0,
            w3.toBytes(hexstr="00"),
            w3.toBytes(hexstr="00"),
            {"from": pytest.account},
        )
        pytest.token_facet.receiveWithAuthorization(
            pytest.ZERO_ADDRESS,
            pytest.other_account.address,
            0,
            0,
            0,
            w3.toBytes(hexstr="00"),
            0,
            w3.toBytes(hexstr="00"),
            w3.toBytes(hexstr="00"),
            {"from": pytest.account},
        )

    tx = pytest.token_facet.unBlacklist(
        pytest.other_account.address, {"from": pytest.account}
    )
    tx.wait(1)
    time.sleep(5)

    tx = pytest.token_facet.updateBlacklister(
        pytest.other_account.address, {"from": pytest.account}
    )
    tx.wait(1)
    time.sleep(5)


def test_012_token_facet_rescuable(global_var):
    """
    Functions:
        function rescueERC20(IERC20 _tokenContract, address _to, uint256 _amount) external;
        updateRescuer(address _newRescuer) external;
    """
    with reverts("Caller is not the rescuer"):
        pytest.token_facet.rescueERC20(
            interface.IERC20(pytest.token_facet.address),
            pytest.account.address,
            pytest.TEST_AMOUNT,
            {"from": pytest.account},
        )

    tx = pytest.token_facet.updateRescuer(
        pytest.other_account.address, {"from": pytest.account}
    )
    tx.wait(1)
    time.sleep(5)

    tx = pytest.token_facet.transfer(
        pytest.token_facet.address, pytest.TEST_AMOUNT, {"from": pytest.account}
    )
    tx.wait(1)
    time.sleep(5)

    pre_rescue_balance_from = pytest.token_facet.balanceOf(pytest.token_facet.address)
    pre_rescue_balance_to = pytest.token_facet.balanceOf(pytest.account.address)

    assert pre_rescue_balance_from == pytest.TEST_AMOUNT

    expected_balance_from = pre_rescue_balance_from - pytest.TEST_AMOUNT
    expected_balance_to = pre_rescue_balance_to + pytest.TEST_AMOUNT

    tx = pytest.token_facet.rescueERC20(
        interface.IERC20(pytest.token_facet.address),
        pytest.account.address,
        pytest.TEST_AMOUNT,
        {"from": pytest.other_account},
    )

    tx.wait(1)
    time.sleep(5)

    post_rescue_balance_from = pytest.token_facet.balanceOf(pytest.token_facet.address)
    post_rescue_balance_to = pytest.token_facet.balanceOf(pytest.account.address)

    assert post_rescue_balance_from == expected_balance_from
    assert post_rescue_balance_to == expected_balance_to
