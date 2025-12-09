// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

/**
 * @dev Contract Layout based on RareSkills Solidity Style guide
 * here: https://www.rareskills.io/post/solidity-style-guide which expounds on
 * Solidity's recommended guide on the docs.
 * Type Declarations
 * State Variables
 * Events
 * Errors
 * Modifiers
 * Constructor
 * receive
 * fallback
 * Functions:
 *  External
 *      External View
 *      External pure
 *  Public
 *      Public View
 *      Public pure
 *  Internal
 *      Internal View
 *      Internal Pure
 *  Private
 *      Private View
 *      Private Pure
 *
 */

/// @title Vault Contract
/// @author n7es1
/// @notice A vault contract that allows users to deposit ETH and receive rebase tokens, and redeem rebase tokens for ETH.
contract Vault {
    IRebaseToken private immutable i_rebaseToken;

    event Vault__Deposited(address user, uint256 amount);
    event Vault__Redeemed(address user, uint256 amount);

    error Vault__RedeemFailed();

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    /// @notice Receive function to accept ETH deposits directly as rewards for user to withdraw later
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Get the address of the rebase token associated with the vault
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }

    /// @notice Deposit ETH into the vault in exchange for rebase tokens
    function deposit() external payable {
        i_rebaseToken.mint(msg.sender, msg.value);
        emit Vault__Deposited(msg.sender, msg.value);
    }

    /// @notice Redeem rebase tokens in exchange for ETH from the vault
    /// @param _amount The amount of rebase tokens to redeem
    function redeem(uint256 _amount) external {
        i_rebaseToken.burn(msg.sender, _amount);
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Vault__Redeemed(msg.sender, _amount);
    }
}
