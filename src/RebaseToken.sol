// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

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

import {ERC20} from "@openzeppelin/contracts@5.5.0/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts@5.5.0/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts@5.5.0/access/AccessControl.sol";

/**
 * @title Cross Chain Rebase Token
 * @author Nzesi
 * @notice A cross chain rebase token that incentivizes users to deposit into a vault and earn an interest.
 * @notice The interest rate in this protocol can only decrease over time.
 * @notice Each user has their own interest rate which is the global interest rate at the time of entry.
 * @dev The protocol's total supply function will not reflect the interest accrued. Only individual balances will
 * reflect the interest accrued.
 */

contract RebaseToken is ERC20, Ownable, AccessControl {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @dev Global Interest Rate per second
    uint256 private s_interestRate = 5e10; // 0.00000005% per second
    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 public constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    mapping(address => uint256) private s_userInterestRates;
    mapping(address => uint256) private s_userLastUpdatedAt;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    /// @dev Event emitted once a new Interest rate is set.
    /// @param oldInterestRate The old Interest rate
    /// @param newInterestRate The updated Interest rate
    event RebaseToken__InterestRateUpdated(uint256 oldInterestRate, uint256 newInterestRate);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    /// @dev Revert error when attempting to set a higher interest rate than the current one.
    error RebaseToken__InterestRateCanOnlyBeDecreased();

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the global interest rate
     * @param _newInterestRate The new interest rate to set
     * @dev The interest rate can only reduce relative to the current rate.
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        if (s_interestRate < _newInterestRate) {
            revert RebaseToken__InterestRateCanOnlyBeDecreased();
        } else {
            s_interestRate = _newInterestRate;
            emit RebaseToken__InterestRateUpdated(s_interestRate, _newInterestRate);
        }
    }

    /**
     * @notice Grants the MINT_AND_BURN_ROLE to `_account`
     * @param _account The account to grant the role to
     * @dev Only callable by the contract owner. Calls the internal `_grantRole` function from AccessControl which has
     * no access restriction by default.
     */
    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice Mints `_amount` amount of Rebase tokens to `_to`
     * @param _to User address
     * @param _amount Amount to mint
     */
    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRates[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burns `_amount` amount of Rebase tokens from `_from`
     * @param _from User address
     * @param _amount Amount to burn. If set to `type(uint256).max`, it burns the user's entire balance.
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Fetches the stored interest rate of a user.
     * @param _user The user whom to fetch the interest rate for
     * @return The interest rate of a user.
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRates[_user];
    }

    /**
     * @notice Fetches the current global interest rate set for future depositers.
     * @return The global interest rate.
     */
    function getGlobalInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /**
     * @notice Fetches the principal balance of a user, excluding any interest accrued since the last update.
     * @param _user The user whom to fetch the principal balance for
     * @return The principal balance of a user.
     */
    function getPrincipalBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Returns the user's current balance including interest accrued since the last update. i.e., since the last
     * time they interacted with the protocol(mint, burn, transfer etc)
     * @param _user The address of the user.
     * @return The principal balance multiplied by the linear interest factor, scaled back down by 1e18.
     *
     * @dev The principal balance (the amount of tokens originally minted to the user) is obtained from
     *      the parent ERC20 contract's `balanceOf()`. This function applies linear interest of the form:
     *
     *          P(t) = P0 * (1 + r * t)
     *
     *      where:
     *        - P0 is the principal balance
     *        - r is the user's interest rate, in 1e18 fixed-point precision
     *        - t is the elapsed time since the last update
     *
     *      The interest factor `(1 + r * t)` is computed in fixed-point as:
     *
     *          interestFactor = 1e18 + (r * t) --> in the `_computeInterestFactorSinceLastUpdate` function
     *
     *      The final result is:
     *
     *          balance = principal * interestFactor / 1e18
     *
     *      This function therefore returns the up-to-date balance including accumulated interest.
     */

    function balanceOf(address _user) public view override returns (uint256) {
        return (super.balanceOf(_user) * _computeInterestFactorSinceLastUpdate(_user) / PRECISION_FACTOR);
    }

    /**
     * @notice Transfers `_amount` of tokens from the caller to `_to`, minting any accrued interest for both parties.
     * @param _to The recipient address.
     * @param _amount The amount to transfer. If set to `type(uint256).max`, transfers the caller's entire balance.
     * @return A boolean indicating success.
     *
     * @dev Before executing the transfer, this function mints any accrued interest for both the sender
     *      and recipient by calling `_mintAccruedInterest()`. This ensures that both parties' balances
     *      are up to date with interest before the transfer occurs.
     *
     *      If the recipient has no existing balance, their interest rate is initialized to match
     *      that of the sender, inheriting the sender's rate at the time of transfer.
     *
     *      Finally, the function calls the parent ERC20 `transfer()` method to perform the actual token transfer.
     */
    function transfer(address _to, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_to);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }

        if (balanceOf(_to) == 0) {
            s_userInterestRates[_to] = s_userInterestRates[msg.sender];
        }

        return super.transfer(_to, _amount);
    }

    /**
     * @notice Transfers `_amount` of tokens from `_from` to `_to`, minting any accrued interest for both parties.
     * @param _from The sender address.
     * @param _to The recipient address.
     * @param _amount The amount to transfer. If set to `type(uint256).max`, transfers the sender's entire balance.
     * @return A boolean indicating success.
     *
     * @dev Before executing the transfer, this function mints any accrued interest for both the sender
     *      and recipient by calling `_mintAccruedInterest()`. This ensures that both parties' balances
     *      are up to date with interest before the transfer occurs.
     *
     *      If the recipient has no existing balance, their interest rate is initialized to match
     *      that of the sender, inheriting the sender's rate at the time of transfer.
     *
     *      Finally, the function calls the parent ERC20 `transferFrom()` method to perform the actual token transfer.
     */
    function transferFrom(address _from, address _to, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_from);
        _mintAccruedInterest(_to);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }

        if (balanceOf(_to) == 0) {
            s_userInterestRates[_to] = s_userInterestRates[_from];
        }

        return super.transferFrom(_from, _to, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Mints the interest that has accrued for a user since their last update timestamp.
     * @param _user The address receiving accrued interest.
     *
     * @dev This function computes how much interest the user has earned by:
     *      1. Reading the user's previously minted principal balance (`super.balanceOf`).
     *      2. Computing the up-to-date balance including linear interest (`balanceOf`).
     *      3. Subtracting principal from updated balance to obtain the interest amount.
     *
     *      The difference represents the number of new RBT tokens that must be minted
     *      to bring the user's balance up to date.
     *
     *      After minting the interest, the user's last updated timestamp is refreshed.
     */
    function _mintAccruedInterest(address _user) internal {
        uint256 previousPrincipalBalance = super.balanceOf(_user);
        uint256 updatedBalanceWithInterest = balanceOf(_user);
        uint256 interestToBeMinted = updatedBalanceWithInterest - previousPrincipalBalance;
        s_userLastUpdatedAt[_user] = block.timestamp;
        _mint(_user, interestToBeMinted);
    }

    /**
     * @notice Calculates the user's accumulated interest since the last update timestamp.
     * @param _user The address of the user whose interest is being calculated.
     * @return The linear interest growth factor since the last update, scaled by 1e18.
     *
     * @dev This function returns only the *interest factor*, not the updated balance. The principal
     *      is already accounted for in `balanceOf()`. The returned value represents:
     *
     *          1e18 + (rate * elapsedTime)
     *
     *      where:
     *        - The interest rate is expressed in 1e18 precision
     *        - `1e18` represents the "1" in the linear-growth formula: suppose P is the principal,
     *
     *              P(t) = P0 * (1 + r * t)
     *
     *      but scaled by 1e18 for fixed-point math. This function therefore returns only:
     *
     *              (1 + r * t)   →   (1e18 + r * t)
     *
     *      as a fixed-point multiplier. The caller multiplies this factor by the principal and
     *      scales down by 1e18 to obtain the actual accumulated interest.
     */

    function _computeInterestFactorSinceLastUpdate(address _user) internal view returns (uint256) {
        // Time elapsed since the user's last interest update
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedAt[_user];

        // Linear interest factor:
        //     1e18 + (rate * timeElapsed)
        // This corresponds to: (1 + r * t) in fixed-point form.
        //
        // Example:
        //   principal = 10 tokens
        //   rate = 0.5% = 0.005e18
        //   t = 2 seconds
        //
        //   interestFactor = 1e18 + (0.005e18 * 2)
        //   updatedAmount = principal * interestFactor / 1e18
        //
        // The 1e18 represents the constant "1" in the formula, scaled for precision.
        uint256 linearInterest = PRECISION_FACTOR + (s_userInterestRates[_user] * timeElapsed);
        return linearInterest;
    }
}
