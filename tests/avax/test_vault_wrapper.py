import brownie
from brownie import interface, accounts
import pytest


def transfer_from_whale(whale, account, token, amount):
    token.transfer(account, amount, {"from": whale})


def approve_wrapper(account, wrapper, token, amount):
    token.approve(wrapper, amount, {"from": account})


ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

# user refers accounts[3]
def test_referral_single_user(user, vault, wrapper, token, whale, amount, gov):
    wrapper.approveVault(vault, {"from": gov})
    transfer_from_whale(whale, accounts[3], token, amount)

    # accounts[3] should approve wrapper first
    with brownie.reverts():
        wrapper.deposit(amount, user, vault, {"from": accounts[3]})
    approve_wrapper(accounts[3], wrapper, token, amount)

    print("User balance before ", token.balanceOf(accounts[3]))
    tx = wrapper.deposit(amount, user, vault, {"from": accounts[3]})

    assert wrapper.referrals(accounts[3]) == user
    with pytest.raises(brownie.exceptions.EventLookupError):
        tx.events["ReferrerChanged"]
    assert len(tx.events["ReferrerSet"]) == 1

    referrerSetEvent = tx.events["ReferrerSet"][0]
    assert referrerSetEvent["account"] == accounts[3]
    assert referrerSetEvent["referrer"] == user

    # accounts[3] should have all the receipt tokens
    assert len(tx.events["Deposit"]) == 1
    depositEvent = tx.events["Deposit"][0]
    assert depositEvent["recipient"] == accounts[3]
    assert depositEvent["amount"] == amount

    assert vault.balanceOf(wrapper) == 0
    assert vault.balanceOf(accounts[3]) == depositEvent["shares"]

    # accounts[3] should be able to withdraw
    vault.withdraw(depositEvent["shares"], {"from": accounts[3]})
    assert vault.balanceOf(accounts[3]) == 0
    assert token.balanceOf(accounts[3]) > 0

    print("User balance after ", token.balanceOf(accounts[3]))


# user refers user, should revert
def test_referral_self_referral(user, vault, wrapper, token, whale, amount, gov):
    wrapper.approveVault(vault, {"from": gov})
    transfer_from_whale(whale, user, token, amount)
    approve_wrapper(user, wrapper, token, amount)

    with brownie.reverts():
        wrapper.deposit(amount, user, vault, {"from": user})


# user refers accounts[3], then accounts[4] refers accounts[3], wrapper.referrals() should stay user
def test_referral_double_deposit_different_referrers(
    user, vault, wrapper, token, whale, amount, gov
):
    wrapper.approveVault(vault, {"from": gov})
    transfer_from_whale(whale, accounts[3], token, amount)
    approve_wrapper(accounts[3], wrapper, token, amount)

    tx = wrapper.deposit(amount, user, vault, {"from": accounts[3]})

    assert wrapper.referrals(accounts[3]) == user
    with pytest.raises(brownie.exceptions.EventLookupError):
        tx.events["ReferrerChanged"]
    assert len(tx.events["ReferrerSet"]) == 1

    referrerSetEvent = tx.events["ReferrerSet"][0]
    assert referrerSetEvent["account"] == accounts[3]
    assert referrerSetEvent["referrer"] == user

    transfer_from_whale(whale, accounts[3], token, amount)
    approve_wrapper(accounts[3], wrapper, token, amount)

    tx = wrapper.deposit(amount, accounts[4], vault, {"from": accounts[3]})

    assert wrapper.referrals(accounts[3]) == user

    with pytest.raises(brownie.exceptions.EventLookupError):
        tx.events["ReferrerChanged"]
    with pytest.raises(brownie.exceptions.EventLookupError):
        tx.events["ReferrerSet"]


# Testing calling deposit passing 0x0 as ref
def test_deposit_zero_ref(user, vault, wrapper, token, whale, amount, gov, treasury):
    wrapper.approveVault(vault, {"from": gov})
    transfer_from_whale(whale, user, token, amount)
    approve_wrapper(user, wrapper, token, amount)
    tx = wrapper.deposit(amount, ZERO_ADDRESS, vault, {"from": user})

    assert wrapper.referrals(user) == treasury
    with pytest.raises(brownie.exceptions.EventLookupError):
        tx.events["ReferrerChanged"]
    assert len(tx.events["ReferrerSet"]) == 1

    referrerSetEvent = tx.events["ReferrerSet"][0]
    assert referrerSetEvent["account"] == user
    assert referrerSetEvent["referrer"] == treasury


# test allow/revoke vault
def test_allow_revoke_vault(user, vault, wrapper, token, whale, amount, gov):
    transfer_from_whale(whale, accounts[3], token, amount)
    approve_wrapper(accounts[3], wrapper, token, amount)

    # gov have not approved the vault, should revert
    with brownie.reverts():
        wrapper.deposit(amount, user, vault, {"from": accounts[3]})

    wrapper.approveVault(vault, {"from": gov})

    tx = wrapper.deposit(amount, user, vault, {"from": accounts[3]})

    assert wrapper.referrals(accounts[3]) == user
    with pytest.raises(brownie.exceptions.EventLookupError):
        tx.events["ReferrerChanged"]
    assert len(tx.events["ReferrerSet"]) == 1

    referrerSetEvent = tx.events["ReferrerSet"][0]
    assert referrerSetEvent["account"] == accounts[3]
    assert referrerSetEvent["referrer"] == user

    # revoking the vault, no new deposits
    wrapper.revokeVault(vault, {"from": gov})

    transfer_from_whale(whale, accounts[3], token, amount)
    approve_wrapper(accounts[3], wrapper, token, amount)

    # gov have not approved the vault, should revert
    with brownie.reverts():
        wrapper.deposit(amount, user, vault, {"from": accounts[3]})

    # only gov can approve/revoke vaults
    with brownie.reverts():
        wrapper.revokeVault(vault, {"from": user})

    with brownie.reverts():
        wrapper.approveVault(vault, {"from": user})


# testing override
def test_override_referrals(user, vault, wrapper, token, whale, amount, gov, treasury):
    wrapper.approveVault(vault, {"from": gov})
    transfer_from_whale(whale, accounts[3], token, amount)
    transfer_from_whale(whale, accounts[4], token, amount)

    approve_wrapper(accounts[3], wrapper, token, amount)
    approve_wrapper(accounts[4], wrapper, token, amount)

    wrapper.deposit(amount, user, vault, {"from": accounts[3]})
    wrapper.deposit(amount, user, vault, {"from": accounts[4]})

    # only gov can change referrals
    with brownie.reverts():
        wrapper.overrideReferrer(accounts[3], accounts[5], {"from": accounts[5]})

    tx = wrapper.overrideReferrer(accounts[3], accounts[5], {"from": gov})
    assert wrapper.referrals(accounts[3]) == accounts[5]
    assert len(tx.events["ReferrerChanged"]) == 1

    referrerChangedEvent = tx.events["ReferrerChanged"][0]
    assert referrerChangedEvent["account"] == accounts[3]
    assert referrerChangedEvent["oldReferrer"] == user
    assert referrerChangedEvent["newReferrer"] == accounts[5]

    # test default referral
    wrapper.removeReferrer(accounts[3], {"from": gov})
    assert wrapper.referrals(accounts[3]) == treasury

    # test override with 0x0 to reset referrals
    wrapper.overrideReferrer(accounts[4], ZERO_ADDRESS, {"from": gov})
    assert wrapper.referrals(accounts[4]) == ZERO_ADDRESS


# testing onlyOwner
def test_only_owner_functions(
    user, vault, gov, wrapper, token, whale, amount, treasury
):
    with brownie.reverts():
        wrapper.setTreasury(accounts[6], {"from": user})
    assert wrapper.treasury() == treasury

    wrapper.setTreasury(accounts[6], {"from": gov})
    assert wrapper.treasury() == accounts[6]

    # Transfer ownership
    with brownie.reverts():
        wrapper.transferOwnership(accounts[6], {"from": user})
    wrapper.transferOwnership(accounts[6], {"from": gov})

    assert wrapper.owner() == accounts[6]
