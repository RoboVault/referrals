// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IVault.sol";

/// @title Referral Vault Wrapper
/// @author RoboVault
/// @notice A vault wrapper that's intend for use in conjunction with The Graph protocol to coordinate
/// a vault referral program.
contract ReferralVaultWrapper is Ownable {
    /// @param _treasury treasury address
    constructor(address _treasury) {
        treasury = _treasury;
    }

    /*///////////////////////////////////////////////////////////////
                            TREASURY STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Default address for users with no referrer
    address public treasury;

    /// @notice Emitted when the treasury is changed
    event TreasuryUpdated(address oldTreasury, address newTreasury);

    /// @notice Update the treasury address.
    /// @param _newTreasury new treasury address
    function setTreasury(address _newTreasury) external onlyOwner {
        address old = treasury;
        treasury = _newTreasury;
        emit TreasuryUpdated(old, treasury);
    }

    /*///////////////////////////////////////////////////////////////
                            APPROVED VAULT STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice mapping of vaults the owner of the contract has approved. Given users will
    /// be approving this contract to spend tokens, only approved vaults tokens are allowed
    /// for use.
    mapping(address => bool) public approvedVaults;

    /// @notice Emits when a vault is permitted or revoked
    event VaultStatusChanged(address vault, bool allowed);

    /// @notice Approves a vault to be used with this wrapper
    /// @param _vault address to the vualt
    function approveVault(address _vault) external onlyOwner {
        approvedVaults[_vault] = true;
        emit VaultStatusChanged(_vault, true);
    }

    /// @notice Revoke permission for a vault
    /// @param _vault address to the vualt
    function revokeVault(address _vault) external onlyOwner {
        approvedVaults[_vault] = false;
        emit VaultStatusChanged(_vault, false);
    }

    /*///////////////////////////////////////////////////////////////
                            REFERRER STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @notice assigned referrers for each user. This is set once on the first deposit
    mapping(address => address) public referrals;

    /// @notice Emits when a referrer is set
    event ReferrerSet(address account, address referrer);

    /// @notice Emits when a referrer is changed. Only owner can change the referrer
    event ReferrerChanged(
        address account,
        address oldReferrer,
        address newReferrer
    );

    /// @notice Overwrites the referrer for a given address
    /// @param _account account address owner is overwriting
    /// @param _newReferrer the new referrer
    function overrideReferrer(address _account, address _newReferrer)
        external
        onlyOwner
    {
        _overrideReferrer(_account, _newReferrer);
    }

    /// @notice Removes the referrer for _account by setting the referrer to treasury
    /// @param _account account address owner is overwriting
    function removeReferrer(address _account) external onlyOwner {
        _overrideReferrer(_account, treasury);
    }

    /// @notice Internal overrideReferrer()
    /// @param _account account address owner is overwriting
    /// @param _newReferrer the new referrer
    function _overrideReferrer(address _account, address _newReferrer)
        internal
    {
        emit ReferrerChanged(_account, referrals[_account], _newReferrer);
        referrals[_account] = _newReferrer;
    }

    /*///////////////////////////////////////////////////////////////
                           VAULT WRAPPER
    //////////////////////////////////////////////////////////////*/

    /// @notice deposit wrapper. Deposits on behalf of a user and sets the referrer
    /// @param _amount amount of vault.token()'s to be deposited on behalf of msg.sender
    /// @param _referrer Referrer address. Zero address will default to treasury address. The user cannot refer themselves.
    /// @param _vault Vault to deposit user funds into
    function deposit(
        uint256 _amount,
        address _referrer,
        address _vault
    ) external returns (uint256) {
        require(_referrer != msg.sender); // @dev: self_referral
        require(approvedVaults[_vault]); // @dev: unsupported_vault
        if (_referrer == address(0)) _referrer = treasury;
        address recipient = msg.sender;
        IERC20(IVault(_vault).token()).transferFrom(
            recipient,
            address(this),
            _amount
        );
        IERC20(IVault(_vault).token()).approve(_vault, _amount);
        if (referrals[recipient] == address(0)) {
            referrals[recipient] = (_referrer == address(0))
                ? treasury
                : _referrer;
            emit ReferrerSet(recipient, referrals[recipient]);
        }
        return IVault(_vault).deposit(_amount, recipient);
    }
}
