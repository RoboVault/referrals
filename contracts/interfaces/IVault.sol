// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVault is IERC20 {
    /// @notice deposits amount in tokens into vault.
    function deposit(uint256 amount, address recipient)
        external
        returns (uint256);

    /// @notice withdraw amount in shares from the vault.
    function withdraw(uint256 maxShares) external returns (uint256);

    /// @notice returns the underlying of the vault.
    function token() external view returns (address);
}
