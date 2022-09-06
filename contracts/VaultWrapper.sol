// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IVault.sol";

contract VaultWrapper is Ownable {
    address public treasury; //Default address for the ones that deposit without a referral code

    mapping(address => address) referrals;

    constructor(address _treasury) public {
        treasury = _treasury;
    }

    event ReferrerSet(
        address account,
        address referrer
    );


    function deposit(uint256 amount, address referrer, address vault) external returns (uint256) {
        address recipient = msg.sender;
        IERC20(IVault(vault).token()).transferFrom(recipient, address(this), amount);

        if(referrals[recipient] == address(0)) {
            referrals[recipient] = (referrer == address(0))?treasury:referrer;
            emit ReferrerSet(recipient, referrals[recipient]);
        }

        return IVault(vault).deposit(amount, recipient);
    }

    function setTreasury(address newAddress) external onlyOwner {
        treasury = newAddress;
    } 
}