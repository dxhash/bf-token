# Fiat token

## Setup

Requirements:
- python >= 3.10

```
python -m pip install -r requirements.txt
```

## Compile

```
brownie compile
```

## Testing

First, make sure Ganache is running.

```
ganache-cli.cmd -p 7545 --mnemonic "laugh rib burger art horror response sunny team volume antique east" --networkId 5777 --db
```

If doesn't already exist, add ganache-local network to brownie.

```
brownie networks add Ethereum ganache-local host=http://0.0.0.0:7545 chainid=5777
```

Deploy contracts to ganache-local network

```
brownie run scripts/deploy.py --network ganache-local
```

Run all tests:

```
brownie test -s --network ganache-local
```

To run specific test, run:

```
brownie test -s -k "test_000_some_test" --network ganache-local
```


## Deployment

Create the file `.env`. Set PRIVATE_KEY, WEB3_INFURA_PROJECT_ID, ETHERSCAN_TOKEN variables. This file must not be checked into the repository. To prevent
accidental check-ins, `.env` is in `.gitignore`.

Run `brownie run scripts/deploy.py migrate --network NETWORK`, where NETWORK is either `mainnet` or `rinkeby`.


## Contracts

The implementation uses few separate contracts - a Diamond proxy contract based
on EIP 2535 (`Diamond.sol`) and an facet implementation contracts (`facets/TokenFacet.sol`,
`facets/OwnershipFacet.sol`, `facets/DiamondLoupeFacet.sol`, `facets/DiamondCutFacet.sol`).
This allows upgrading the contract or add new features, as a new implementation
contacts can be deployed and the Proxy updated to point to it.

### EIP-2535 Diamonds

EIP-2535 Diamonds is a contract standard that standardizes contract interfaces and implementation
details to implement the diamond pattern. The standardization makes integration with tools and other
software possible.

The diamond pattern is a contract that uses a fallback function to delegate function calls to multiple
other contracts called facets. Conceptually a diamond can be thought of as a contract that gets its
external functions from other contracts. A diamond has four standard functions (called the loupe)
that report what functions and facets a diamond has. A diamond has a DiamondCut event that reports all
functions/facets that are added/replaced/removed on a diamond, making upgrades on diamonds transparent.

The diamond pattern is a code implementation and organization strategy. The diamond pattern makes it
possible to implement a lot of contract functionality that is compartmented into separate areas of
functionality, but still using the same Ethereum address. The code is further simplified and saves gas
because state variables are shared between facets.

Diamonds are not limited by the maximum contract size which is 24KB.

Facets can be deployed once and reused by any number of diamonds. Diamonds can be upgradeable or immutable.
They can be upgradeable and at a later date become immutable. Diamonds support fine-grained upgrades which
means it is possible to add/replace/remove only the parts desired. Everything does not have to be redeployed
in order to make a change. A diamond does not solve all upgrade issues and problems but makes some things
easier and better.

See the [standard](https://eips.ethereum.org/EIPS/eip-2535) and the [standard's reference section](https://eips.ethereum.org/EIPS/eip-2535#learning--references) for more information about diamonds.

Information about the deployed Diamond can be seen in [louper.dev](https://louper.dev), a user interface for diamonds.

### Loupe Functions
To find out what functions and facets the Diamond has the loupe functions can be called.

The facetAddresses() function returns all the Ethereum addresses of all facets used by a diamond.

The facetFunctionSelectors(address _facet) function is used to return all the 4-byte function selectors
of a facet that is used by a diamond. The 4-byte function selectors and the ABI of a facet are used to get
the function names and arguments.

The facetAddress(bytes4 _functionSelector) function returns the facet address used by a diamond for the
4-byte function selector that is provided.

The facets() function returns all the facet addresses and function selectors used by a diamond.


### Upgradeability
EIP-2535 Diamond Standard specifies the diamondCut function to upgrade diamonds.

The  diamondCut function can be used to add and/or replace and/or remove any number of functions in a single
transactions. This enables a number of specific changes to occur at the same time which prevents a diamond
from getting into a bad or inconsistent state.

Anytime functions are added/replaced/removed the DiamondCut event is emitted. This provides a historical and
transparent record of all changes to a diamond over time.

The standard does allow custom upgrade functions to be implemented for diamonds. But in any case the DiamondCut
event must be emitted for all functions that are added, replaced or removed.

### Facets
A facet is a contract whose external functions are added to a diamond to give the diamond functionality.
All the functions from the facets documented on this website, such as OwnershipFacet, TokenFacet etc, are
added to Diamond when it is deployed.

The external functions defined in the facets can be called on the Diamond Ethereum address.

Facets that are added to the same diamond can share the same state variables.

The maximum number of selectors in a facet is 256.

### OwnershipFacet

The OwnershipFacet implements ERC173 interface.

### TokenFacet

The TokenFacet implements ERC20, EIP3612 and EIP3009 interfaces.

### Pausable

The entire contract can be frozen, in case a serious bug is found or there is a
serious key compromise. No transfers can take place while the contract is
paused. Access to the pause functionality is controlled by the `pauser` address.

### Blacklist

The contract can blacklist certain addresses which will prevent those addresses
from transferring or receiving tokens. Access to the blacklist functionality is
controlled by the `blacklister` address.

### Minting/Burning

Tokens can be minted or burned on demand. The contract supports having multiple
minters simultaneously. The mint allowance is similar to the ERC20 allowance - as
each minter mints new tokens their allowance decreases. When it gets too low they
will need the allowance increased again by the `owner`. Minters are also allowed
to burn tokens they own.

### Ownable

The contract has an Owner, who can change the `owner`, `pauser`, `blacklister`,
or `minter` addresses.

### Rescueble

`rescuer` address is able to rescue any ERC20 tokens locked up in this contract.