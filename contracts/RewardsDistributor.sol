// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/cryptography/MerkleProof.sol";
import "./interfaces/IMerkleDistributor.sol";

/// @notice The code is a modified version of https://github.com/Uniswap/merkle-distributor/blob/master/contracts/MerkleDistributor.sol
contract RewardsDistributor is IMerkleDistributor, Ownable {
    bytes32 public override rewardsRoot;

    address public treasury; //Send some funds back if we find a bad actor that needs to be blacklisted

    address[] public vaults;

    // This is a packed array of booleans.
    mapping(uint256 => uint256) private claimedBitMap;
    mapping(address => bool) private blacklistedAddress;

    constructor(address _treasury) public {
        //TODO setup roles for
        // - blacklist
        // - update merkle root
        treasury = _treasury;
    }

    //Vaults cannot be removed. In case of a migration to another vault, just add a new vault and set all the rewards to 0 on the old vault
    function addVault(address _vault) external onlyOwner {
        vaults.push(_vault);
    }

    //TODO dedicated role
    function updateRewardsRoot(bytes32 _rewardsRoot) external onlyOwner {
        rewardsRoot = _rewardsRoot;
    }

    //TODO add role for blacklist
    function blacklistUser(address _user) external onlyOwner {
        blacklistedAddress[_user] = true;
        //TODO emit event
    }

    //TODO add role for blacklist
    function removeBlacklistUser(address _user) external onlyOwner {
        blacklistedAddress[_user] = false;
        //TODO emit event
    }

    function isClaimed(uint256 index) public view override returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function _setClaimed(uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[claimedWordIndex] = claimedBitMap[claimedWordIndex] | (1 << claimedBitIndex);
    }


    function _claimInternal(uint256 index, address account, uint256[] amounts, bytes32[] calldata merkleProof, address actualReceiver) {
        require(!isClaimed(index), 'RewardsDistributor: Reward already claimed.');

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, account, amounts));
        require(MerkleProof.verify(merkleProof, rewardsRoot, node), 'RewardsDistributor: Invalid proof.');

        // Mark it claimed and send the token.
        _setClaimed(index);
        for(uint256 i = 0; i < amounts.length; i++) {
            if(amounts[i] != 0) {
                require(IERC20(vaults[i]).transfer(actualReceiver, amounts[i]), 'RewardsDistributor: Transfer failed.');
            }
        }
    }


    function claimRewardsBlackList(uint256 index, address account, uint256[] amounts, bytes32[] calldata merkleProof) external onlyOwner {
        _claimInternal(index, account, amounts, merkleProof, treasury);
        //TODO emit event blacklist claim
    }

    function claim(uint256 index, uint256[] amounts, bytes32[] calldata merkleProof) external override {
        require(!blacklistedAddress[msg.sender], 'RewardsDistributor: Address blacklisted.');
        _claimInternal(index, msg.sender, amounts, merkleProof, msg.sender);
        emit Claimed(index, msg.sender, amounts);

    }
}