import pytest
from brownie import config
from brownie import ReferralVaultWrapper
from brownie import interface, project, accounts

 # TODO - Pull from coingecko

CONFIG = {
    'USDC': {
        'token': '0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E',
        'whale': '0xB715808a78F6041E46d61Cb123C9B4A27056AE9C',
        'vault': '0x49d743E645C90ef4c6D5134533c1e62D08867b14',
    },
}

@pytest.fixture
def token_name():
    yield "USDC"
    # yield "WETH"

@pytest.fixture
def conf(token_name):
    yield CONFIG[token_name]

@pytest.fixture
def gov(accounts):
    #yield accounts.at("0x7601630eC802952ba1ED2B6e4db16F699A0a5A87", force=True)
    yield accounts[1]

@pytest.fixture
def user(accounts):
    yield accounts[0]


@pytest.fixture
def treasury(accounts):
    yield accounts[2]


@pytest.fixture
def token(conf):
    yield interface.IERC20Extended(conf['token'])

@pytest.fixture
def whale(conf, accounts) : 
    yield accounts.at(conf['whale'], True)

@pytest.fixture
def amount(token, whale):
    amount = 10_000 * 10 ** token.decimals()
    amount = min(amount, int(0.5*token.balanceOf(whale)))
    yield amount

@pytest.fixture
def vault(conf):
    vault = interface.IVault(conf['vault'])
    yield vault

@pytest.fixture
def wrapper(gov, treasury):
    vaultWrapper = gov.deploy(ReferralVaultWrapper, treasury)
    yield vaultWrapper


@pytest.fixture(scope="session")
def RELATIVE_APPROX():
    yield 1e-5




