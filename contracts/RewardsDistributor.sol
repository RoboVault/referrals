// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title Referrals Rewards Distributor
/// @author RoboVault
/// @notice This contract makes it possible to withdraw the earned rewards (referrals, rebates) for users.
/// The amounts are calculated offchain with TheGraph
/// The code is a modified version of https://github.com/Uniswap/merkle-distributor/blob/master/contracts/MerkleDistributor.sol
contract RewardsDistributor is AccessControlEnumerable {
    /// @notice Roles
    bytes32 public constant GOV_ROLE = keccak256("GOV_ROLE");
    bytes32 public constant BLACKLIST_ROLE = keccak256("BLACKLIST_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @param _treasury treasury address
    constructor(address _treasury) {
        governance = msg.sender;
        
        _setRoleAdmin(BLACKLIST_ROLE, GOV_ROLE);
        _setRoleAdmin(MANAGER_ROLE, GOV_ROLE);
        
        _grantRole(GOV_ROLE, msg.sender);
        _grantRole(BLACKLIST_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);

        treasury = _treasury;
    }

    /*///////////////////////////////////////////////////////////////
                            GOV STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Used to send some funds back if we find a bad actor that needs to be blacklisted, or for emergency withdrawals
    address public governance;
    /// @notice Emitted when the treasury is changed
    event GovernanceUpdated(address oldGovernance, address newGovernance);

    /// @notice Update the governance address.
    /// @param _newGovernance new treasury address
    function setGovernance(address _newGovernance) external onlyRole(GOV_ROLE) {
        require(_newGovernance != address(0));
        address old = governance;
        _grantRole(GOV_ROLE, _newGovernance);
        _revokeRole(GOV_ROLE, governance);
        governance = _newGovernance;
        emit GovernanceUpdated(old, governance);
    }

    /*///////////////////////////////////////////////////////////////
                            TREASURY STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Used to send some funds back if we find a bad actor that needs to be blacklisted, or for emergency withdrawals
    address public treasury;
    /// @notice Emitted when the treasury is changed
    event TreasuryUpdated(address oldTreasury, address newTreasury);

    /// @notice Update the treasury address.
    /// @param _newTreasury new treasury address
    function setTreasury(address _newTreasury) external onlyRole(GOV_ROLE) {
        require(_newTreasury != address(0));
        address old = treasury;
        treasury = _newTreasury;
        emit TreasuryUpdated(old, treasury);
    }

    /*///////////////////////////////////////////////////////////////
                            VAULTS STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @notice Array with the vaults addresses
    address[] public vaults;

    /// @notice Adds a vault to the array.
    /// msg.sender must have MANAGER_ROLE
    /// @dev Vaults cannot be removed. In case of a migration to another vault, just add a new vault and set all the rewards to 0 on the old vault
    /// @param _vault the address of the asset to add to the array, if it is not already present
    function addVault(address _vault) external onlyRole(MANAGER_ROLE) {
        for (uint256 i = 0; i < vaults.length; i++) {
            require(vaults[i] != _vault, "Asset already present");
        }
        vaults.push(_vault);
        emit VaultAdded(_vault);
    }

    /// @notice Emits when a vault is added
    event VaultAdded(address vault);

    /*///////////////////////////////////////////////////////////////
                            EMERGENCY MODE
    //////////////////////////////////////////////////////////////*/

    /// @notice if true, all claims are paused and GOV_ROLE can withdraw all tokens
    bool public emergencyMode;

    /// @notice Emits when either emergencyWithdrawMulti() or emergencyWithdrawSingle() is called
    event EmergencyWithdraw(address asset);

    /// @notice Emits when emergencyMode is activated or deactivated
    event EmergencyModeUpdated(bool isEmergencyModeActive);

    /// @notice GOV_ROLE or MANAGER_ROLE can enable emergencyMode
    function enableEmergencyMode() external {
        require(
            hasRole(GOV_ROLE, msg.sender) || hasRole(MANAGER_ROLE, msg.sender)
        );
        emergencyMode = true;
        emit EmergencyModeUpdated(true);
    }

    /// @notice only GOV_ROLE can disable emergencyMode
    function disableEmergencyMode() external onlyRole(GOV_ROLE) {
        emergencyMode = false;
        emit EmergencyModeUpdated(false);
    }

    /// @notice In case of emergency, gov can withdraw everything from the contract and send it to the treasury
    /// The event fired will have `asset` set to 0x0
    function emergencyWithdrawMulti() external onlyRole(GOV_ROLE) {
        require(emergencyMode, "Emergency Mode not enabled");
        for (uint256 i = 0; i < vaults.length; i++) {
            require(
                IERC20(vaults[i]).transfer(
                    treasury,
                    IERC20(vaults[i]).balanceOf(address(this))
                )
            );
        }
        emit EmergencyWithdraw(address(0));
    }

    /// @notice In case of emergency, gov can withdraw an asset from the smart contract, and send it to the treasury
    /// @param _asset address of the asset to withdraw
    function emergencyWithdrawSingle(address _asset)
        external
        onlyRole(GOV_ROLE)
    {
        require(emergencyMode, "Emergency Mode not enabled");
        require(
            IERC20(_asset).transfer(
                treasury,
                IERC20(_asset).balanceOf(address(this))
            )
        );
        emit EmergencyWithdraw(_asset);
    }

    /*///////////////////////////////////////////////////////////////
                            BLACKLIST MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice keeps a record of blacklistedAddresses. Can only be modified by BLACKLIST_ROLE
    mapping(address => bool) public blacklistedAddresses;

    /// @notice emits when claimBlacklist() is called.
    event BlacklistClaimed(
        uint256 period,
        uint256 index,
        address blackListedAccount,
        uint256[] amounts,
        address claimedTo
    );

    /// @notice emits when the blacklist changes
    event BlackListUpdated(address user, bool isBlacklisted);

    /// @notice Blacklist a user. Only BLACKLIST_ROLE can call this function
    /// @param _user the address to blacklist
    function blacklistUser(address _user) external onlyRole(BLACKLIST_ROLE) {
        blacklistedAddresses[_user] = true;
        emit BlackListUpdated(_user, true);
    }

    /// @notice Remove a user from the blacklist. Only BLACKLIST_ROLE can call this function
    /// @param _user the address to remove from the blacklist
    function removeBlacklistUser(address _user)
        external
        onlyRole(BLACKLIST_ROLE)
    {
        blacklistedAddresses[_user] = false;
        emit BlackListUpdated(_user, false);
    }

    /*///////////////////////////////////////////////////////////////
                           MERKLE TREE
    //////////////////////////////////////////////////////////////*/

    /// @notice mapping from the period to the root of the merkle tree representing the rewards for that period
    mapping(uint256 => bytes32) public merkleRoots;

    /// @notice fires when the merkle root for a new period is updated
    event MerkleRootUpdated(bytes32 merkleRoot, uint256 period);

    /// @notice updates merkleRoots
    /// @param _root the root node of the merkle tree representing the rewards for `period` period
    /// @param _period an integer repre
    function updateMerkleRoot(bytes32 _root, uint256 _period)
        external
        onlyRole(MANAGER_ROLE)
    {
        require(merkleRoots[_period] == 0, "Alrady set");
        merkleRoots[_period] = _root;
        emit MerkleRootUpdated(_root, _period);
    }

    /*///////////////////////////////////////////////////////////////
                           CLAIMED
    //////////////////////////////////////////////////////////////*/

    /// @notice claimedBitMap[period] is a bitMap to check if a user has already claimed his rewards
    mapping(uint256 => mapping(uint256 => uint256)) private claimedBitMap;

    /// @notice checks if a reward has already been claimed
    /// @param _period an uin256 that increases every time new rewards are ready to be claimed.
    /// @param _index a number linked to the user
    function isClaimed(uint256 _period, uint256 _index)
        public
        view
        returns (bool)
    {
        uint256 claimedWordIndex = _index / 256;
        uint256 claimedBitIndex = _index % 256;
        uint256 claimedWord = claimedBitMap[_period][claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    /// @notice sets a reward as claimed
    /// @param _period an uin256 that increases every time new rewards are ready to be claimed.
    /// @param _index a number linked to the user
    function _setClaimed(uint256 _period, uint256 _index) private {
        uint256 claimedWordIndex = _index / 256;
        uint256 claimedBitIndex = _index % 256;
        claimedBitMap[_period][claimedWordIndex] =
            claimedBitMap[_period][claimedWordIndex] |
            (1 << claimedBitIndex);
    }

    /*///////////////////////////////////////////////////////////////
                            REWARDS DISTRIBUTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice fires whenever claim() is called
    event ReferralsClaimed(
        uint256 period,
        uint256 index,
        address account,
        uint256[] amounts
    );

    /// @notice fires whenever claimMultiple() is called
    event ReferralsClaimedMultiple(
        uint256[] periods,
        uint256[] indexes,
        address account
    );

    /// @notice this function checks that the the address is blacklisted, and then calls the _claim() function to send the funds back to the treasury
    /// @param _period an uin256 that increases every time new rewards are ready to be claimed.
    /// @param _index a number linked to `msg.sender`
    /// @param _account the address of the blacklisted account
    /// @param _amounts an array with the correct amounts of rewards expected
    /// @param _merkleProof the merkle proof generated using https://www.npmjs.com/package/merkletreejs
    function claimBlacklist(
        uint256 _period,
        uint256 _index,
        address _account,
        uint256[] calldata _amounts,
        bytes32[] calldata _merkleProof
    ) external onlyRole(BLACKLIST_ROLE) {
        require(blacklistedAddresses[_account], "Address not blacklisted");
        _claim(_period, _index, _account, _amounts, _merkleProof, treasury);
        emit BlacklistClaimed(_period, _index, _account, _amounts, treasury);
    }

    /// @notice this function checks that the the address is not blacklisted, and then calls the _claim() function
    /// @param _period an uin256 that increases every time new rewards are ready to be claimed.
    /// @param _index a number linked to `msg.sender`
    /// @param _amounts an array with the correct amounts of rewards expected
    /// @param _merkleProof the merkle proof generated using https://www.npmjs.com/package/merkletreejs
    function claim(
        uint256 _period,
        uint256 _index,
        uint256[] calldata _amounts,
        bytes32[] calldata _merkleProof
    ) external {
        require(!blacklistedAddresses[msg.sender], "Address blacklisted");
        _claim(_period, _index, msg.sender, _amounts, _merkleProof, msg.sender);
        emit ReferralsClaimed(_period, _index, msg.sender, _amounts);
    }

    /// @notice this function performs multiple claims for different periods
    /// @param _periods an uin256 that increases every time new rewards are ready to be claimed. @see
    /// @param _indexes a number linked to `msg.sender`
    /// @param _amounts an array with the correct amounts of rewards expected
    /// @param _merkleProofs the merkle proof generated using https://www.npmjs.com/package/merkletreejs
    function claimMultiple(
        uint256[] calldata _periods,
        uint256[] calldata _indexes,
        uint256[][] calldata _amounts,
        bytes32[][] calldata _merkleProofs
    ) external {
        require(_periods.length == _indexes.length, "Wrong length"); // @dev: RewardsDistributor: invalid lengths of parameters
        require(_periods.length == _amounts.length, "Wrong length"); // @dev: RewardsDistributor: invalid lengths of parameters
        require(_periods.length == _merkleProofs.length, "Wrong length"); // @dev: RewardsDistributor: invalid lengths of parameters
        require(!blacklistedAddresses[msg.sender], "Address blacklisted");
        for (uint256 i = 0; i < _periods.length; i++) {
            _claim(
                _periods[i],
                _indexes[i],
                msg.sender,
                _amounts[i],
                _merkleProofs[i],
                msg.sender
            );
            emit ReferralsClaimed(
                _periods[i],
                _indexes[i],
                msg.sender,
                _amounts[i]
            );
        }
        emit ReferralsClaimedMultiple(_periods, _indexes, msg.sender);
    }

    /// @notice this function checks that the reward can be claimed, then sends the tokens to the `actualReceiver`
    /// @param _period an uin256 that increases every time new rewards are ready to be claimed.
    /// @param _index a number linked to the user
    /// @param _account the account to claims the rewards for
    /// @param _amounts an array with the correct amounts of rewards expected
    /// @param _merkleProof the merkle proof generated using https://www.npmjs.com/package/merkletreejs
    /// @param _actualReceiver the address to send the tokens to. This can either be `msg.sender` or `treasury`
    function _claim(
        uint256 _period,
        uint256 _index,
        address _account,
        uint256[] calldata _amounts,
        bytes32[] calldata _merkleProof,
        address _actualReceiver
    ) internal {
        require(!emergencyMode, "Emergency mode is active, rewards are paused");
        require(!isClaimed(_period, _index), "Reward already claimed");

        // Verify the merkle proof.
        bytes32 node = keccak256(
            abi.encode(_period, _index, _account, _amounts)
        );
        require(
            MerkleProof.verify(_merkleProof, merkleRoots[_period], node),
            "Invalid proof"
        );

        // Mark it claimed and send the tokens
        _setClaimed(_period, _index);
        /// @dev There is no need to check that amounts[]'s length is <= vaults[]'s length, cause the MerkleProof will fail for a different (wrong) number of amounts
        for (uint256 i = 0; i < _amounts.length; i++) {
            if (_amounts[i] != 0) {
                require(
                    IERC20(vaults[i]).transfer(_actualReceiver, _amounts[i]),
                    "Transfer failed"
                );
            }
        }
    }
}
