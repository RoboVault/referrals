import brownie
from brownie import interface, accounts, convert
import pytest

TEST_PERIOD = 0
TEST_ADDRESSES = ["0x5c90f12606a4b72374a7ed6dc84d5d10d7154cfb","0x328d4c0306c6c6ee066309ec69d1cc7ce9641463","0xfde4528d0bb3851c4032337b59d68c8075d2289f","0xfea789d02772175912cf8433c779b0ca87a28739"]
TEST_AMOUNTS = [[800000 ,400000000000000000 ],[900000 ,300000000000000000 ],[300000 ,200000000000000000 ],[400000 ,100000000000000000 ]]
TEST_PROOFS = [["0x9619e1708659c59fb4145b1ca0b806300c2e4d4267cde3380acebf14693d01e6","0x3a56d7331db31f253f83d48ead0f081e4a64e6147c3ba197dff9bb06d2ca2bfa"],["0x22b5a91452e9357b555b4d7f8a8d98a1a847e18d5604a5c140dddcce026efe56","0x3a56d7331db31f253f83d48ead0f081e4a64e6147c3ba197dff9bb06d2ca2bfa"],["0xdb3cce9dad881999cfcfe61d1c4a7bf4545b140244ad4af3834695d26e710e4f","0x59131c2dab92a2d48c55ed3591c61c45818ccecd59e6242eddb6a01d5d5294bc"],["0x339ad117aa46140d1cec736ddae64c551b769886f1688bcdfcec62d04fe28999","0x59131c2dab92a2d48c55ed3591c61c45818ccecd59e6242eddb6a01d5d5294bc"]]
TEST_ROOT_HASH = "5380a77810dc481431fa26cc69bee2c3881a0d37c20067c7d0fecf170f394cd4"

TEST_PERIOD_2 = 1
TEST_AMOUNTS_2 = [[400000 ,300000000000000000 ],[300000 ,500000000000000000 ],[700000 ,600000000000000000 ],[900000 ,400000000000000000 ]]
TEST_PROOFS_2 = [["0xab875d9843513001ae48889aa4f1927d4d65d9912d1c43a27562e094d699cc0a","0x4e26923014f3fc23d258537c7abac3804e79e7651201435e488ab84ee6c399e6"],["0x45e0702f999425a09ce89b77dcbf1715050b00cfa2fd6dabd464f29a84756a0a","0x4e26923014f3fc23d258537c7abac3804e79e7651201435e488ab84ee6c399e6"],["0x9438f79b1821e445366dc622e108a7879dbff9c68d1e451070abb17a737a9330","0x1985af0acb65bf0c87b65872ec37918edcf0377a746bbf5b9f4d8d7108a57c52"],["0x439fb8418a62b5c29163b269c25795851caf8c5259bfb92859f647f61587ff3c","0x1985af0acb65bf0c87b65872ec37918edcf0377a746bbf5b9f4d8d7108a57c52"]]
TEST_ROOT_HASH_2 = "e1f759505b2d2fa01469dc146dba48951c84d1ed37ecab543b55f8d5b1847dee"

USDC_VAULT = "0x49d743E645C90ef4c6D5134533c1e62D08867b14"
WETH_VAULT = "0x7fc282B1B6162733084eE3F882624e2BD1ed941E"

USDC_VAULT_WHALE = "0x4c6062eda9d53d749e6e1ab1676b27aa5730c03f"
WETH_VAULT_WHALE = "0x65877be34c0c3c3a317d97028fd91bd261410026"

GOV_ROLE = "0603f2636f0ca34ae3ea5a23bb826e2bd2ffd59fb1c01edc1ba10fba2899d1ba"
BLACKLIST_ROLE = "22435ed027edf5f902dc0093fbc24cdb50c05b5fd5f311b78c67c1cbaff60e13"
MANAGER_ROLE = "241ecf16d79d0f8dbfb92cbc07fe17840425976cf0667f022fe9877caa831b08"

@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass


@pytest.fixture
def setup_distributor(distributor, gov):
    # Gov setup the Root hash for period 0 and 1
    distributor.updateMerkleRoot(TEST_ROOT_HASH, TEST_PERIOD, {"from": gov})
    distributor.updateMerkleRoot(TEST_ROOT_HASH_2, TEST_PERIOD_2, {"from": gov})
    with brownie.reverts():
        distributor.updateMerkleRoot(TEST_ROOT_HASH, TEST_PERIOD_2, {"from": gov})
    # Activate USDC vault
    distributor.addVault(USDC_VAULT, {"from": gov})
    # Activate WETH vault
    distributor.addVault(WETH_VAULT, {"from": gov})
    #Transfer some rUSDC to the distributor
    rUSDC = interface.IERC20Extended(USDC_VAULT)
    rETH = interface.IERC20Extended(WETH_VAULT)
    rUSDC.transfer(distributor.address, rUSDC.balanceOf(USDC_VAULT_WHALE), {"from": accounts.at(USDC_VAULT_WHALE, True)})
    #Transfer some rETH to the distributor
    rETH.transfer(distributor.address, rETH.balanceOf(WETH_VAULT_WHALE), {"from": accounts.at(WETH_VAULT_WHALE, True)})
    print("Balance of distributor: ", rUSDC.balanceOf(distributor), " USDC")
    print("Balance of distributor: ", rETH.balanceOf(distributor), " WETH")


def test_roles(distributor, setup_distributor, gov):
    addr1 = accounts.at(TEST_ADDRESSES[0], True)
    addr2 = accounts.at(TEST_ADDRESSES[1], True)
    # gov can change roles
    distributor.grantRole(BLACKLIST_ROLE, addr1, {"from": gov})
    distributor.grantRole(BLACKLIST_ROLE, addr2, {"from": gov})

    # addr1, addr2 now can blacklist people
    distributor.blacklistUser(TEST_ADDRESSES[-1], {"from": addr1})

    # addr1 renounce role
    distributor.renounceRole(BLACKLIST_ROLE, addr1, {"from": addr1})

    # only gov can remove revoke roles
    with brownie.reverts():
        distributor.revokeRole(BLACKLIST_ROLE, addr2, {"from": addr2})
    distributor.revokeRole(BLACKLIST_ROLE, addr2, {"from": gov})

    # MANAGER_ROLE
    distributor.grantRole(MANAGER_ROLE, addr1, {"from": gov})

    # addr1 can now set emergency/add vaults/add roots
    distributor.enableEmergencyMode({"from": addr1})

    # GOV_ROLE: switching out gov
    
    # only someone with GOV_ROLE can set the governance
    with brownie.reverts():
        distributor.setGovernance(addr2, {"from": addr1})
    distributor.setGovernance(addr2, {"from": gov})

    # gov now can't change roles
    with brownie.reverts():
        distributor.revokeRole(GOV_ROLE, addr1, {"from": gov})

    # addr2 is the new gov
    assert distributor.governance() == addr2
    distributor.revokeRole(MANAGER_ROLE, addr1, {"from": addr2})
    distributor.setTreasury(TEST_ADDRESSES[-2], {"from": addr2})

    # GOV_ROLE cannot be added with grantRole
    with brownie.reverts():
        distributor.grantRole(GOV_ROLE, addr1, {"from": addr2})


def test_claim_reward_basic(distributor, setup_distributor, gov):
    referrer_account = accounts.at(TEST_ADDRESSES[0], True)

    distributor.claim(TEST_PERIOD, 1, TEST_AMOUNTS[0], TEST_PROOFS[0], {"from": referrer_account})
    rUSDC = interface.IERC20Extended(USDC_VAULT)
    rETH = interface.IERC20Extended(WETH_VAULT)
    assert rUSDC.balanceOf(referrer_account) == TEST_AMOUNTS[0][0]
    assert rETH.balanceOf(referrer_account) == TEST_AMOUNTS[0][1]

def test_claim_double_should_fail(distributor, setup_distributor, gov):
    referrer_account = accounts.at(TEST_ADDRESSES[0], True)

    distributor.claim(TEST_PERIOD, 1, TEST_AMOUNTS[0], TEST_PROOFS[0], {"from": referrer_account})
    rUSDC = interface.IERC20Extended(USDC_VAULT)
    rETH = interface.IERC20Extended(WETH_VAULT)
    assert rUSDC.balanceOf(referrer_account) == TEST_AMOUNTS[0][0]
    assert rETH.balanceOf(referrer_account) == TEST_AMOUNTS[0][1]

    with brownie.reverts("Reward already claimed"):
        distributor.claim(TEST_PERIOD, 1, TEST_AMOUNTS[0], TEST_PROOFS[0], {"from": referrer_account})

    assert rUSDC.balanceOf(referrer_account) == TEST_AMOUNTS[0][0]
    assert rETH.balanceOf(referrer_account) == TEST_AMOUNTS[0][1]

    # claim multiple fails if any one of the single claim fails
    with brownie.reverts("Reward already claimed"):
        distributor.claimMultiple([0,1], [1,1], [TEST_AMOUNTS[0], TEST_AMOUNTS_2[0]], [TEST_PROOFS[0], TEST_PROOFS_2[0]], {"from": referrer_account})
    
def test_claim_multiple(distributor, setup_distributor, gov):
    referrer_account = accounts.at(TEST_ADDRESSES[0], True)

    distributor.claimMultiple([0,1], [1,1], [TEST_AMOUNTS[0], TEST_AMOUNTS_2[0]], [TEST_PROOFS[0], TEST_PROOFS_2[0]], {"from": referrer_account})
    rUSDC = interface.IERC20Extended(USDC_VAULT)
    rETH = interface.IERC20Extended(WETH_VAULT)
    assert rUSDC.balanceOf(referrer_account) == TEST_AMOUNTS[0][0] + TEST_AMOUNTS_2[0][0]
    assert rETH.balanceOf(referrer_account) == TEST_AMOUNTS[0][1] + TEST_AMOUNTS_2[0][1]


def test_invalid_claims(distributor, setup_distributor, gov):
    # Wrong address, proof should be invalid
    wrong_address = accounts.at(TEST_ADDRESSES[1], True)
    with brownie.reverts("Invalid proof"):
        distributor.claim(TEST_PERIOD, 1, TEST_AMOUNTS[0], TEST_PROOFS[0], {"from": wrong_address})

    referrer_account = accounts.at(TEST_ADDRESSES[0], True)
    # Wrong index 
    with brownie.reverts("Invalid proof"):
        distributor.claim(TEST_PERIOD, 999, TEST_AMOUNTS[0], TEST_PROOFS[0], {"from": referrer_account})

    # Wrong amount 
    with brownie.reverts("Invalid proof"):
        distributor.claim(TEST_PERIOD, 1, TEST_AMOUNTS[1], TEST_PROOFS[0], {"from": referrer_account})


    # Wrong proof 
    with brownie.reverts("Invalid proof"):
        distributor.claim(TEST_PERIOD, 1, TEST_AMOUNTS[1], TEST_PROOFS[1], {"from": referrer_account})

    # Incomplete proof
    # Wrong proof 
    with brownie.reverts("Invalid proof"):
        distributor.claim(TEST_PERIOD, 1, TEST_AMOUNTS[1], [TEST_PROOFS[0][0]], {"from": referrer_account})

def test_blacklist(distributor, setup_distributor, gov):
    blacklisted_account = accounts.at(TEST_ADDRESSES[0], True)
    potential_attacker = accounts.at(TEST_ADDRESSES[1], True)

    with brownie.reverts("Address not blacklisted"):
        distributor.claimBlacklist(TEST_PERIOD, 1, blacklisted_account, TEST_AMOUNTS[0], TEST_PROOFS[0], {"from": gov})


    # only BLACKLIST_ROLE can change the blacklist
    with brownie.reverts():
        distributor.blacklistUser(blacklisted_account, {"from": potential_attacker})
    # blacklist the account
    distributor.blacklistUser(blacklisted_account, {"from": gov})
    
    # blacklisted_account can't withdraw
    with brownie.reverts("Address blacklisted"):
        distributor.claim(TEST_PERIOD, 1, TEST_AMOUNTS[0], TEST_PROOFS[0], {"from": blacklisted_account})
    with brownie.reverts("Address blacklisted"):
        distributor.claimMultiple([0,1], [1,1], [TEST_AMOUNTS[0], TEST_AMOUNTS_2[0]], [TEST_PROOFS[0], TEST_PROOFS_2[0]], {"from": blacklisted_account})
    # blacklisted_account can't call claimBlackList 
    with brownie.reverts():
        distributor.claimBlacklist(TEST_PERIOD, 1, blacklisted_account, TEST_AMOUNTS[0], TEST_PROOFS[0], {"from": blacklisted_account})
    # BLACKLIST_ROLE can call claimBlacklist
    distributor.claimBlacklist(TEST_PERIOD, 1, blacklisted_account, TEST_AMOUNTS[0], TEST_PROOFS[0], {"from": gov})

    # only BLACKLIST_ROLE can remove blacklist
    with brownie.reverts():
        distributor.removeBlacklistUser(blacklisted_account, {"from": potential_attacker})
    distributor.removeBlacklistUser(blacklisted_account, {"from": gov})

    # now blacklisted_account can claim the rewards of the periods not claimed from BLACKLIST_ROLE, and BLACKLIST_ROLE can't claim other rewards
    with brownie.reverts("Address not blacklisted"):
        distributor.claimBlacklist(TEST_PERIOD_2, 1, blacklisted_account, TEST_AMOUNTS_2[0], TEST_PROOFS_2[0], {"from": gov})
    distributor.claim(TEST_PERIOD_2, 1, TEST_AMOUNTS_2[0], TEST_PROOFS_2[0], {"from": blacklisted_account})

    rUSDC = interface.IERC20Extended(USDC_VAULT)
    rETH = interface.IERC20Extended(WETH_VAULT)
    assert rUSDC.balanceOf(blacklisted_account) == TEST_AMOUNTS_2[0][0]
    assert rETH.balanceOf(blacklisted_account) == TEST_AMOUNTS_2[0][1]


def test_emergency(distributor, setup_distributor, gov, treasury):
    user = accounts.at(TEST_ADDRESSES[0], True)

    # Activate emergency mode
    with brownie.reverts():
        distributor.enableEmergencyMode({"from": user})
    distributor.enableEmergencyMode({"from": gov})
    # Test that users can't withdraw
    with brownie.reverts():
        distributor.claim(TEST_PERIOD, 1, TEST_AMOUNTS[0], TEST_PROOFS[0], {"from": user})
    # Gov can withdraw 1 token to treasury
    with brownie.reverts():
        distributor.emergencyWithdrawSingle(USDC_VAULT, {"from": user})
    distributor.emergencyWithdrawSingle(USDC_VAULT, {"from": gov})
    # Gov can withdraw ALL tokens to treasury
    with brownie.reverts():
        distributor.emergencyWithdrawMulti({"from": user})
    distributor.emergencyWithdrawMulti({"from": gov})
    # Gov can deactivate emergency mode
    with brownie.reverts():
        distributor.disableEmergencyMode({"from": user})
    distributor.disableEmergencyMode({"from": gov})
    # Transfer funds back into the distributor
    rUSDC = interface.IERC20Extended(USDC_VAULT)
    rETH = interface.IERC20Extended(WETH_VAULT)
    rUSDC.transfer(distributor.address, rUSDC.balanceOf(treasury), {"from": treasury})
    rETH.transfer(distributor.address, rETH.balanceOf(treasury), {"from": treasury})
    # Users can now withdraw
    distributor.claim(TEST_PERIOD, 1, TEST_AMOUNTS[0], TEST_PROOFS[0], {"from": user})
    # emergencyWithdraw can't be called right now
    with brownie.reverts("Emergency Mode not enabled"):
        distributor.emergencyWithdrawSingle(USDC_VAULT, {"from": gov})
    with brownie.reverts("Emergency Mode not enabled"):
        distributor.emergencyWithdrawMulti({"from": gov})

