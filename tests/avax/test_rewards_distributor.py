import brownie
from brownie import interface, accounts, convert
import pytest

def test_claim_reward_basic(user, vault, distributor, token, whale, amount, gov):
    assert 1 == 0