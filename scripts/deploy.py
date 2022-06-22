from brownie import (
    accounts,
    interface,
    network,
    chain,
    config,
    Contract,
    DiamondCutFacet,
    Diamond,
    DiamondInit,
    DiamondLoupeFacet,
    OwnershipFacet,
    TokenFacet,
)


def deploy_diamond():

    account = accounts.add(config["networks"][network.show_active()]["from_key"])
    print(f"Account: {account}")

    active_network = network.show_active()
    print(f"Network: {active_network}")

    diamond_cut_facet = DiamondCutFacet.deploy(
        {"from": account},
        publish_source=config["networks"][active_network].get("verify"),
    )
    diamond = Diamond.deploy(
        account,
        diamond_cut_facet.address,
        {"from": account},
        publish_source=config["networks"][active_network].get("verify"),
    )
    diamond_init = DiamondInit.deploy(
        {"from": account},
        publish_source=config["networks"][active_network].get("verify"),
    )
    diamond_loupe_facet = DiamondLoupeFacet.deploy(
        {"from": account},
        publish_source=config["networks"][active_network].get("verify"),
    )
    ownership_facet = OwnershipFacet.deploy(
        {"from": account},
        publish_source=config["networks"][active_network].get("verify"),
    )
    token_facet = TokenFacet.deploy(
        {"from": account},
        publish_source=config["networks"][active_network].get("verify"),
    )

    # Add=0, Replace=1, Remove=2

    cut = [
        [diamond_loupe_facet.address, 0, list(diamond_loupe_facet.selectors.keys())],
        [ownership_facet.address, 0, list(ownership_facet.selectors.keys())],
        [token_facet.address, 0, list(token_facet.selectors.keys())],
    ]

    diamond_cut = interface.IDiamondCut(diamond.address)
    function_call = diamond_init.init.encode_input()

    tx = diamond_cut.diamondCut(
        cut,
        diamond_init.address,
        function_call,
        {"from": account},
    )
    tx.wait(1)

    print("Completed diamond cut")

    token_facet = Contract.from_abi("TokenFacet", diamond.address, abi=TokenFacet.abi)

    token_facet.setup(
        config["token"]["name"],
        config["token"]["version"],
        config["token"]["symbol"],
        config["token"]["decimals"],
        {"from": account},
    )

    print("Completed token setup")

    return diamond.address


def main():
    deploy_diamond()
