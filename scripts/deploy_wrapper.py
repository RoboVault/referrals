from pathlib import Path

from brownie import VaultWrapper, accounts, config, network, project, web3
from eth_utils import is_checksum_address
import click


def get_address(msg: str, default: str = None) -> str:
    val = click.prompt(msg, default=default)

    # Keep asking user for click.prompt until it passes
    while True:

        if is_checksum_address(val):
            return val
        elif addr := web3.ens.address(val):
            click.echo(f"Found ENS '{val}' [{addr}]")
            return addr

        click.echo(
            f"I'm sorry, but '{val}' is not a checksummed address or valid ENS record"
        )
        # NOTE: Only display default once
        val = click.prompt(msg)


def main():
    print(f"You are using the '{network.show_active()}' network")
    dev = accounts.load(click.prompt("Account", type=click.Choice(accounts.load())))
    print(f"You are using: 'dev' [{dev.address}]")

    treasury = get_address('Treasury address: ')
    
    publish_source = click.confirm("Verify source on etherscan?")
    if input("Deploy Wrapper? y/[N]: ").lower() != "y":
        return

    vaultWrapper = VaultWrapper.deploy(treasury, {"from": dev}, publish_source=publish_source)