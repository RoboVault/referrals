import brownie
from brownie import interface, accounts
import pytest

def transfer_from_whale(whale, account, token, amount):
    token.transfer(account, amount, {'from': whale})

def approve_wrapper(account, wrapper, token, amount):
    token.approve(wrapper.address, amount, {'from': account})


def test_referral_single_user(user, vault, wrapper, token, whale, amount):
    # user refers accounts[3]
    transfer_from_whale(whale, accounts[3], token, amount)
    approve_wrapper(accounts[3], wrapper, token, amount)

    wrapper.deposit(amount, user, vault.address, {'from': accounts[3]})

    assert wrapper.referrals(accounts[3]) == user.address


def test_referral_self_referral(user, vault, wrapper, token, whale, amount):
    # user refers user, should revert
    transfer_from_whale(whale, user, token, amount)
    approve_wrapper(user, wrapper, token, amount)

    with brownie.reverts():    
        wrapper.deposit(amount, user, vault.address, {'from': user})



