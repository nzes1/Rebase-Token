// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

/// @title Vault Contract
/// @author Nzesi
/// @notice A vault contract that allows users to deposit ETH and receive rebase tokens, and redeem rebase tokens for
/// ETH.
contract Vault {

    IRebaseToken private immutable i_rebaseToken;

    event Vault__Deposited(address indexed user, uint256 amount);
    event Vault__Redeemed(address indexed user, uint256 amount);

    error Vault__RedeemFailed();

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    /// @notice Receive function to accept ETH deposits directly as rewards for users to withdraw later
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
        uint256 interestRate = i_rebaseToken.getGlobalInterestRate();
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Vault__Deposited(msg.sender, msg.value);
    }

    /// @notice Redeem rebase tokens in exchange for ETH from the vault
    /// @param _amount The amount of rebase tokens to redeem
    function redeem(uint256 _amount) external {
        // To avoid dust amounts when users are redeeming their entire balance, we allow them to specify
        // the maximum uint256 value to redeem their entire balance.
        if (_amount == type(uint256).max) _amount = i_rebaseToken.balanceOf(msg.sender);
        i_rebaseToken.burn(msg.sender, _amount);
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) revert Vault__RedeemFailed();
        emit Vault__Redeemed(msg.sender, _amount);
    }

}
