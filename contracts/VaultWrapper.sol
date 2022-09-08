// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IVault.sol";

contract VaultWrapper is Ownable {
    address public treasury; //Default address for the ones that deposit without a referral code
    mapping(address => address) public referrals;

    constructor(address _treasury) public {
        treasury = _treasury;
    }

    event ReferrerChanged(
        address account,
        address oldReferrer,
        address newReferrer
    );

    event ReferrerSet(
        address account,
        address referrer
    );


    function deposit(uint256 amount, address referrer, address vault) external returns (uint256) {
        require(referrer != msg.sender, "self_referral");
        address recipient = msg.sender;
        IERC20(IVault(vault).token()).transferFrom(recipient, address(this), amount);
        IERC20(IVault(vault).token()).approve(vault, amount);
        if(referrals[recipient] == address(0)) {
            referrals[recipient] = (referrer == address(0))?treasury:referrer;
            emit ReferrerSet(recipient, referrals[recipient]);
        }

        return IVault(vault).deposit(amount, recipient);
    }

    function setTreasury(address newAddress) external onlyOwner {
        treasury = newAddress;
    }

    function _overrideReferrerInternal(address account, address newReferrer) internal {
        emit ReferrerChanged(account, referrals[account], newReferrer);
        referrals[account] = newReferrer;
    }

    function overrideReferrer(address account, address newReferrer) external onlyOwner {
        _overrideReferrerInternal(account, newReferrer);
    }

    function overrideReferrer(address account) external onlyOwner {
        _overrideReferrerInternal(account, treasury);
    }

    function overrideReferrerMultiple(address[] calldata accounts, address newReferrer) external onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            _overrideReferrerInternal(accounts[i], newReferrer);
        }
    }

    function overrideReferrerMultiple(address[] calldata accounts) external onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            _overrideReferrerInternal(accounts[i], treasury);
        }
    }
}