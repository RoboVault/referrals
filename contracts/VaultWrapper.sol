// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IVault.sol";

contract VaultWrapper is Ownable {
    IVault public vault;
    address public treasury; //Default address for the ones that deposit without a referral code
    address public token;

    mapping(address => address) referrals;

    constructor(address _vault, address _treasury) public {
        vault = IVault(_vault);
        token = vault.token();
        treasury = _treasury;
    }

    event ReferrerSet(
        address account,
        address referrer
    );


    function deposit(uint256 amount, address referrer) external returns (uint256) {
        address recipient = msg.sender;

        IERC20(token).transferFrom(recipient, address(this), amount);

        if(referrals[recipient] == address(0)) {
            referrals[recipient] = (referrer == address(0))?treasury:referrer;
            emit ReferrerSet(recipient, referrals[recipient]);
        }

        return vault.deposit(amount, recipient);
    }

    function setVaultAddress(address newAddress) external onlyOwner {
        vault = IVault(newAddress);
    } 

    function setToken(address newAddress) external onlyOwner {
        token = newAddress;
    } 

    function setTreasury(address newAddress) external onlyOwner {
        treasury = newAddress;
    } 
}