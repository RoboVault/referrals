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
    /// @notice default referral code for first time depositors that did not use any code
    bytes32 public constant TREASURY_REF_CODE = "ROBOVAULT";
    
    /// @param _treasury treasury address
    constructor(address _treasury) {
        treasury = _treasury;

        // Registers a default referral code for the treasury
        codeOwners[TREASURY_REF_CODE] = treasury;
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
                            REFERRAL CODES STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice maps a referral codes to his owner
    mapping (bytes32 => address) public codeOwners;

    /// @notice assigned referral codes for each user. This is set once on the first deposit
    mapping (address => bytes32) public userReferralCodes;

    /// @notice emits when a user deposits in a vault for the first time
    event ReferralCodeSet(address account, bytes32 code, address referrer);
    
    /// @notice emits when gov changes the code for a user. This can happen for example if a bad actor is a referrer  
    event ReferralCodeSetGov(address account, bytes32 newCode, bytes32 oldCode, address newReferrer, address oldReferrer);

    /// @notice emits when a referrer registers a new referral code
    event RegisterCode(address account, bytes32 code);

    /// @notice emits when a referrer transfer the ownership of his referral code to another address
    event SetCodeOwner(address oldAccount, address newAccount, bytes32 code);

    /// @notice emits when gov changes the owner of a referral code. This can happen for example if a bad actor is a referrer
    event SetCodeOwnerGov(address oldAccount, address newAccount, bytes32 code);

    /// @notice sets the referral code for a user. Users can't refer themselves
    /// @param _account the account of the user we want to set the referral code for
    /// @param _code string representing a valid referral code
    function _setReferralCode(address _account, bytes32 _code) internal {
        require(codeOwners[_code] != msg.sender, "Self referral"); // @dev: self_referral
        require(codeOwners[_code] != address(0), "Invalid code"); // @dev: Used an invalid code
        // If a user has already used a ref code before, we do not want to update it
        if(userReferralCodes[_account] == bytes32(0)) {
            userReferralCodes[_account] = _code;
            emit ReferralCodeSet(_account, _code, codeOwners[_code]);
        }
    }

    /// @notice gov can use this function to change the referral code of a User
    /// @param _account the account of the user we want to set the referral code for
    /// @param _code string representing a referral code. No checks are performing since it is the gov
    function setReferralCodeGov(address _account, bytes32 _code) external onlyOwner {
        bytes32 oldCode = userReferralCodes[_account];
        userReferralCodes[_account] = _code;
        emit ReferralCodeSetGov(_account, _code, oldCode, codeOwners[_code], codeOwners[oldCode]);
    }

    /// @notice gets the the referral code and the referrer address for `_account`
    /// @param _account the user address
    function getReferralInfo(address _account) external view returns (bytes32, address) {
        bytes32 code = userReferralCodes[_account];
        address referrer;
        if (code != bytes32(0)) {
            referrer = codeOwners[code];
        }
        return (code, referrer);
    }

    /// @notice registers a new referral code
    /// @param _code string with the referral code to register
    function registerCode(bytes32 _code) external {
        require(_code != bytes32(0), "Invalid _code");
        require(codeOwners[_code] == address(0), "Code already exists");

        codeOwners[_code] = msg.sender;
        emit RegisterCode(msg.sender, _code);
    }

    /// @notice transfers the ownership of `_code` from `msg.sender` to `_newAccount`
    /// @param _code string with the referral code 
    /// @param _newAccount the account to transfer the ownership to
    function setCodeOwner(bytes32 _code, address _newAccount) external {
        require(_code != bytes32(0), "Invalid _code");
        require(msg.sender == codeOwners[_code], "Forbidden");

        codeOwners[_code] = _newAccount;
        emit SetCodeOwner(msg.sender, _newAccount, _code);
    }

    /// @notice transfers the ownership of `_code` from `codeOwners[_code]` to `_newAccount`
    /// @param _code string with the referral code 
    /// @param _newAccount the account to transfer the ownership to
    function setCodeOwnerGov(bytes32 _code, address _newAccount) external onlyOwner {
        require(_code != bytes32(0), "Invalid _code");
        address oldAccount = codeOwners[_code];
        codeOwners[_code] = _newAccount;
        emit SetCodeOwnerGov(oldAccount, _newAccount, _code);
    }

    /*///////////////////////////////////////////////////////////////
                           VAULT WRAPPER
    //////////////////////////////////////////////////////////////*/

    /// @notice deposit wrapper. Deposits on behalf of a user and sets the referrer
    /// @param _amount amount of vault.token()'s to be deposited on behalf of msg.sender
    /// @param _code The code of the referrer. Must be a valid code 
    /// The user cannot refer themselves.
    /// @param _vault Vault to deposit user funds into
    function deposit(
        uint256 _amount,
        bytes32 _code,
        address _vault
    ) external returns (uint256) {
        require(_code != bytes32(0), "Invalid ref code"); // @dev: Zero code is not valid
        return _deposit(_amount, _code, _vault);
    }

    /// @notice deposit wrapper for users that do not input a referral code
    /// @param _amount amount of vault.token()'s to be deposited on behalf of msg.sender
    /// @param _vault Vault to deposit user funds into
    function deposit(
        uint256 _amount,
        address _vault
    ) external returns (uint256) {
        return _deposit(_amount, TREASURY_REF_CODE, _vault);
    }


    /// @notice deposits into a vault and sets the referral code
    /// @param _amount amount of vault.token()'s to be deposited on behalf of msg.sender
    /// @param _code The code of the referrer. Must be a valid code 
    /// The user cannot refer themselves.
    /// @param _vault Vault to deposit user funds into
    function _deposit(uint256 _amount, bytes32 _code, address _vault) internal returns (uint256) {
        require(approvedVaults[_vault], "!Vault"); // @dev: unsupported_vault
        address token = IVault(_vault).token();
        IERC20(token).transferFrom(
            msg.sender,
            address(this),
            _amount
        );
        IERC20(token).approve(_vault, _amount);
        _setReferralCode(msg.sender, _code);
        return IVault(_vault).deposit(_amount, msg.sender);
    }
}
