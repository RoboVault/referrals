import brownie
from brownie import interface, accounts, convert
import pytest


def transfer_from_whale(whale, account, token, amount):
    token.transfer(account, amount, {"from": whale})


def approve_wrapper(account, wrapper, token, amount):
    token.approve(wrapper, amount, {"from": account})


ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
REF_CODE_1 = "CODE1"
REF_CODE_2 = "CODE2"
TREASURY_REF_CODE = "ROBOVAULT"

#@pytest.mark.skip
# user refers accounts[3]
def test_referral_single_user(user, vault, wrapper, token, whale, amount, gov):
    wrapper.approveVault(vault, {"from": gov})
    transfer_from_whale(whale, accounts[3], token, amount)

    # user registers REF_CODE_1 
    wrapper.registerCode(REF_CODE_1.encode(), {"from": user})

    # accounts[3] should approve wrapper first
    with brownie.reverts():
        wrapper.deposit(amount, REF_CODE_1.encode(), vault, {"from": accounts[3]})
    approve_wrapper(accounts[3], wrapper, token, amount)

    print("User balance before ", token.balanceOf(accounts[3]))
    tx = wrapper.deposit(amount, REF_CODE_1.encode(), vault, {"from": accounts[3]})

    assert convert.to_string(wrapper.userReferralCodes(accounts[3])).strip("\x00") == REF_CODE_1
    assert convert.to_string(wrapper.getReferralInfo(accounts[3])[0]).strip("\x00") == REF_CODE_1
    assert wrapper.getReferralInfo(accounts[3])[1] == user
    assert len(tx.events["ReferralCodeSet"]) == 1

    referralCodeSet = tx.events["ReferralCodeSet"][0]
    assert referralCodeSet["account"] == accounts[3]
    assert convert.to_string(referralCodeSet["code"]).strip("\x00") == REF_CODE_1
    assert referralCodeSet["referrer"] == user

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

#@pytest.mark.skip
# user refers user, should revert
def test_referral_self_referral(user, vault, wrapper, token, whale, amount, gov):
    wrapper.approveVault(vault, {"from": gov})
    wrapper.registerCode(REF_CODE_1.encode(), {"from": user})

    transfer_from_whale(whale, user, token, amount)
    approve_wrapper(user, wrapper, token, amount)

    with brownie.reverts():
        wrapper.deposit(amount, REF_CODE_1.encode(), vault, {"from": user})

#@pytest.mark.skip
# user refers accounts[3], then accounts[4] refers accounts[3], wrapper.referrals() should stay user
def test_referral_double_deposit_different_referrers(
    user, vault, wrapper, token, whale, amount, gov
):
    wrapper.approveVault(vault, {"from": gov})
    transfer_from_whale(whale, accounts[3], token, amount)
    approve_wrapper(accounts[3], wrapper, token, amount)

    wrapper.registerCode(REF_CODE_1.encode(), {"from": user})

    tx = wrapper.deposit(amount, REF_CODE_1.encode(), vault, {"from": accounts[3]})

    assert wrapper.getReferralInfo(accounts[3])[1] == user
    assert len(tx.events["ReferralCodeSet"]) == 1
    referralCodeSet = tx.events["ReferralCodeSet"][0]
    assert referralCodeSet["account"] == accounts[3]
    assert convert.to_string(referralCodeSet["code"]).strip("\x00") == REF_CODE_1
    assert referralCodeSet["referrer"] == user

    transfer_from_whale(whale, accounts[3], token, amount)
    approve_wrapper(accounts[3], wrapper, token, amount)
    wrapper.registerCode(REF_CODE_2.encode(), {"from": accounts[4]})


    tx = wrapper.deposit(amount, REF_CODE_2.encode(), vault, {"from": accounts[3]})

    assert wrapper.getReferralInfo(accounts[3])[1] == user

    with pytest.raises(brownie.exceptions.EventLookupError):
        tx.events["ReferralCodeSet"]

#@pytest.mark.skip
# Testing calling deposit passing 0x0 as ref
def test_deposit_zero_ref(user, vault, wrapper, token, whale, amount, gov, treasury):
    wrapper.approveVault(vault, {"from": gov})
    transfer_from_whale(whale, user, token, amount)
    approve_wrapper(user, wrapper, token, amount)

    with brownie.reverts():
        wrapper.registerCode(0, {"from": accounts[3]})
    
    with brownie.reverts():
        wrapper.deposit(amount, 0, vault, {"from": user})

    tx = wrapper.deposit(amount, vault, {"from": user})
    assert wrapper.getReferralInfo(user)[1] == treasury
    assert len(tx.events["ReferralCodeSet"]) == 1
    referralCodeSet = tx.events["ReferralCodeSet"][0]
    assert referralCodeSet["account"] == user
    assert convert.to_string(referralCodeSet["code"]).strip("\x00") == TREASURY_REF_CODE
    assert referralCodeSet["referrer"] == treasury

#@pytest.mark.skip
# test allow/revoke vault
def test_allow_revoke_vault(user, vault, wrapper, token, whale, amount, gov):
    transfer_from_whale(whale, accounts[3], token, amount)
    approve_wrapper(accounts[3], wrapper, token, amount)
    wrapper.registerCode(REF_CODE_1.encode(), {"from": user})


    # gov have not approved the vault, should revert
    with brownie.reverts():
        wrapper.deposit(amount, REF_CODE_1.encode(), vault, {"from": accounts[3]})

    wrapper.approveVault(vault, {"from": gov})

    wrapper.deposit(amount, REF_CODE_1.encode(), vault, {"from": accounts[3]})

    
    # testing a deposit with an invalid code
    transfer_from_whale(whale, accounts[3], token, amount)
    approve_wrapper(accounts[3], wrapper, token, amount)

    with brownie.reverts():
        wrapper.deposit(amount, REF_CODE_2.encode(), vault, {"from": accounts[3]})

    # revoking the vault, no new deposits
    wrapper.revokeVault(vault, {"from": gov})


    # gov have not approved the vault, should revert
    with brownie.reverts():
        wrapper.deposit(amount, REF_CODE_1.encode(), vault, {"from": accounts[3]})

    # only gov can approve/revoke vaults
    with brownie.reverts():
        wrapper.approveVault(vault, {"from": user})

    with brownie.reverts():
        wrapper.revokeVault(vault, {"from": user})



# testing override
def test_override_referrals(user, vault, wrapper, token, whale, amount, gov, treasury):
    wrapper.approveVault(vault, {"from": gov})
    transfer_from_whale(whale, accounts[3], token, amount)
    transfer_from_whale(whale, accounts[4], token, amount)

    approve_wrapper(accounts[3], wrapper, token, amount)
    approve_wrapper(accounts[4], wrapper, token, amount)

    wrapper.registerCode(REF_CODE_1.encode(), {"from": user})
    
    # cannot overwrite ref code
    with brownie.reverts():
        wrapper.registerCode(REF_CODE_1.encode(), {"from": accounts[5]})

    wrapper.registerCode(REF_CODE_2.encode(), {"from": accounts[5]})

    wrapper.deposit(amount, REF_CODE_1.encode(), vault, {"from": accounts[3]})
    wrapper.deposit(amount, REF_CODE_1.encode(), vault, {"from": accounts[4]})

    # only gov can change referrals
    with brownie.reverts():
        wrapper.setReferralCodeGov(accounts[3], REF_CODE_2.encode(), {"from": accounts[5]})

    tx = wrapper.setReferralCodeGov(accounts[3], REF_CODE_2.encode(), {"from": gov})
    assert wrapper.getReferralInfo(accounts[3])[1] == accounts[5]
    assert len(tx.events["ReferralCodeSetGov"]) == 1

    referralCodeSetGov = tx.events["ReferralCodeSetGov"][0]
    assert referralCodeSetGov["account"] == accounts[3]
    assert convert.to_string(referralCodeSetGov["newCode"]).strip("\x00")== REF_CODE_2
    assert convert.to_string(referralCodeSetGov["oldCode"]).strip("\x00")== REF_CODE_1
    assert referralCodeSetGov["newReferrer"] == accounts[5]
    assert referralCodeSetGov["oldReferrer"] == user



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
