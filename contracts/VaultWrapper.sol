// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IVault.sol";

contract VaultWrapper is Ownable {
    IVault public vault;
    address public treasury; //Default address for the ones that deposit without a referral code
    mapping(address => address) referrals;

    event DepositReferral(
        address account,
        uint256 sizeDelta,
        address referrer
    );

    event WithdrawReferral(
        address account,
        uint256 sizeDelta,
        address referrer
    );

    event ReferrerChanged(
        address account,
        address oldReferrer,
        address newReferrer
    );

    function deposit(uint256 amount, address referrer) external returns (uint256) {
        address recipient = msg.sender;
        address prevReferrer = referrals[recipient];


        if(prevReferrer == address(0)) {
            referrals[recipient] = (referrer == address(0))?treasury:referrer;
        }else if(prevReferrer != referrer && referrer != address(0)) {
            emit ReferrerChanged(recipient, prevReferrer, referrer);
            //TODO decrease position of old referrer and increase new referrer?
            // uint256 amountAlreadyDeposited = vault.balanceOf(recipient);
            // emit WithdrawReferral(recipient, amountAlreadyDeposited, prevReferrer);
            // emit DepositReferral(recipient, amountAlreadyDeposited, referrer);
        }

        emit DepositReferral(recipient, amount, referrals[recipient]);
        return vault.deposit(amount, recipient);
    }
    
    
    function withdraw(uint256 amount, uint256 maxLoss) external returns (uint256) {
        if(referrals[msg.sender] != address(0)) {
            emit WithdrawReferral(msg.sender, amount, referrals[msg.sender]);
        }
        return vault.withdraw(amount, msg.sender, maxLoss);
    }

    function setVaultAddress(address newAddress) external onlyOwner {
        vault = IVault(newAddress);
    } 

    function setTreasury(address newAddress) external onlyOwner {
        treasury = newAddress;
    } 
}