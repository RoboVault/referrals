// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/cryptography/MerkleProof.sol";

/// @notice The code is a modified version of https://github.com/Uniswap/merkle-distributor/blob/master/contracts/MerkleDistributor.sol
contract RewardsDistributor is AccessControl {
    mapping(uint256 => bytes32) public merkleRoots;

    address public treasury; //Send some funds back if we find a bad actor that needs to be blacklisted / emergency withdrawals
    address[] public vaults;
    
    bytes32 public constant GOV_ROLE = keccak256("GOV_ROLE");
    bytes32 public constant BLACKLIST_ROLE = keccak256("BLACKLIST_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    bool emergencyMode;

    mapping(uint256 => mapping(uint256 => uint256)) private claimedBitMap;
    mapping(address => bool) private blacklistedAddress;

    event MerkleRootUpdated(bytes32 merkleRoot, uint256 period);
    event VaultAdded(address vault);
    event ReferralsClaimed(uint256 period, uint256 index, address account, uint256[] amounts);
    event ReferralsClaimedMulti(uint256[] periods, uint256[] indexes, address account);
    event BlacklistClaimed(uint256 period, uint256 index, address blackListedAccount, uint256[] amounts, address claimedTo);
    event BlackListUpdated(address user, bool isBlacklisted);
    event EmergencyWithdraw(address asset);
    event EmergencyModeUpdated(bool isEmergencyModeActive);

    constructor(address _treasury) public {
        _setRoleAdmin(BLACKLIST_ROLE, GOV_ROLE);
        _setRoleAdmin(MANAGER_ROLE, GOV_ROLE);

        grantRole(GOV_ROLE, msg.sender);
        grantRole(BLACKLIST_ROLE, msg.sender);
        grantRole(MANAGER_ROLE, msg.sender);

        treasury = _treasury;
    }

    //Vaults cannot be removed. In case of a migration to another vault, just add a new vault and set all the rewards to 0 on the old vault
    function addVault(address _vault) external {
        require(hasRole(MANAGER_ROLE, msg.sender));

        vaults.push(_vault);
        emit VaultAdded(_vault);
    }

    function updateMerkleRoot(bytes32 _root, uint256 period) external {
        require(hasRole(MANAGER_ROLE, msg.sender));

        merkleRoots[period] = _root;
        emit MerkleRootUpdated(_root, period);
    }

    function blacklistUser(address _user) external {
        require(hasRole(BLACKLIST_ROLE, msg.sender));

        blacklistedAddress[_user] = true;
        emit BlackListUpdated(_user, true);
    }

    function removeBlacklistUser(address _user) external {
        require(hasRole(BLACKLIST_ROLE, msg.sender));

        blacklistedAddress[_user] = false;
        emit BlackListUpdated(_user, false);
    }

    function isClaimed(uint256 period, uint256 index) public view returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[period][claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function _setClaimed(uint256 period, uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[period][claimedWordIndex] = claimedBitMap[period][claimedWordIndex] | (1 << claimedBitIndex);
    }

    function _claim(uint256 period, uint256 index, address account, uint256[] calldata amounts, bytes32[] calldata merkleProof, address actualReceiver) internal {
        require(!emergencyMode, 'Emergency mode is active, rewards are paused');
        require(!isClaimed(period, index), 'Reward already claimed');
        // FIXME we could remove this require, since the MerkleProof will fail with a wrong length of amounts (different hash)
        require(amounts.length < vaults.length); // @dev: RewardsDistributor: wrong number in amounts array

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(period, index, account, amounts));
        require(MerkleProof.verify(merkleProof, merkleRoots[period], node), 'Invalid proof');

        // Mark it claimed and send the tokens
        _setClaimed(period, index);
        for(uint256 i = 0; i < amounts.length; i++) {
            if(amounts[i] != 0) {
                require(IERC20(vaults[i]).transfer(actualReceiver, amounts[i]), 'Transfer failed');
            }
        }
    }

    function claimRewardsBlackList(uint256 period, uint256 index, address account, uint256[] calldata amounts, bytes32[] calldata merkleProof) external {
        require(hasRole(BLACKLIST_ROLE, msg.sender));
        require(blacklistedAddress[msg.sender]); // @dev: RewardsDistributor: Address not blacklisted
        _claim(period, index, account, amounts, merkleProof, treasury);
        emit BlacklistClaimed(period, index, msg.sender, amounts, treasury);
    }

    function claim(uint256 period, uint256 index, uint256[] calldata amounts, bytes32[] calldata merkleProof) external {
        require(!blacklistedAddress[msg.sender], 'Address blacklisted'); // @dev: RewardsDistributor: Address blacklisted
        _claim(period, index, msg.sender, amounts, merkleProof, msg.sender);
        emit ReferralsClaimed(period, index, msg.sender, amounts);
    }

    function claimMultiple(uint256[] calldata periods, uint256[] calldata indexes, uint256[][] calldata amounts, bytes32[][] calldata merkleProof) external {
        require(periods.length == indexes.length); // @dev: RewardsDistributor: invalid lengths of parameters
        require(periods.length == amounts.length); // @dev: RewardsDistributor: invalid lengths of parameters
        require(periods.length == merkleProof.length); // @dev: RewardsDistributor: invalid lengths of parameters
        for(uint256 i = 0; i < periods.length; i++) {
            _claim(periods[i], indexes[i], msg.sender, amounts[i], merkleProof[i], msg.sender);
            emit ReferralsClaimed(periods[i], indexes[i], msg.sender, amounts[i]);
        }
        emit ReferralsClaimedMulti(periods, indexes, msg.sender);
    }

    // In case of emergency, gov can withdraw everything from the contract
    function emergencyWithdraw() external {
        require(hasRole(GOV_ROLE, msg.sender));
        require(emergencyMode);
        for(uint256 i = 0; i < vaults.length; i++) {
            require(IERC20(vaults[i]).transfer(treasury, IERC20(vaults[i]).balanceOf(address(this))));
        }
        emit EmergencyWithdraw(address(0));
    }

    function emergencyWithdrawSingle(address asset) external {
        require(hasRole(GOV_ROLE, msg.sender));
        require(emergencyMode);
        IERC20(asset).transfer(treasury, IERC20(asset).balanceOf(address(this)));
        for(uint256 i = 0; i < vaults.length; i++) {
            require(IERC20(vaults[i]).transfer(treasury, IERC20(vaults[i]).balanceOf(address(this))));
        }
        emit EmergencyWithdraw(asset);
    }

    function enableEmergencyMode() external {
        require(hasRole(GOV_ROLE, msg.sender));
        emergencyMode = true;
        emit EmergencyModeUpdated(true);
    }

    function disableEmergencyMode() external {
        require(hasRole(GOV_ROLE, msg.sender));
        emergencyMode = false;
        emit EmergencyModeUpdated(false);
    }


}