// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {RebaseToken} from "../../src/RebaseToken.sol";
import {Vault} from "../../src/Vault.sol";
import {IRebaseToken} from "../../src/interfaces/IRebaseToken.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Test, console} from "forge-std/Test.sol";

contract RebaseTokenUnitTest is Test {

    RebaseToken rebaseToken;
    Vault vault;

    address owner = makeAddr("deployer_or_owner");
    address TEST_USER_1 = makeAddr("Test User 1");
    address TEST_USER_2 = makeAddr("Test User 2");

    function setUp() public {
        vm.label(TEST_USER_1, "USER_1");
        vm.label(TEST_USER_2, "USER_2");
        vm.startPrank(owner);
        vm.deal(owner, 10 ether);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        // Add rewards to the vault to simulate external rewards accumulation such as interest rates.
        payable(address(vault)).call{value: 10 ether}("");
        vm.stopPrank();
    }

    function testFuzz_deposit_UsersCanDepositAndEarnLinearInterest(uint256 _amount) public {
        _amount = bound(_amount, 5e17, type(uint96).max);
        vm.deal(TEST_USER_1, _amount);

        vm.startPrank(TEST_USER_1);
        vault.deposit{value: _amount}();
        vm.stopPrank();

        // Warp to 2 hours and store the balance as bal1 - then repeat for two more rounds
        vm.warp(block.timestamp + 2 hours);
        uint256 bal1 = rebaseToken.balanceOf(TEST_USER_1);

        vm.warp(block.timestamp + 2 hours);
        uint256 bal2 = rebaseToken.balanceOf(TEST_USER_1);

        vm.warp(block.timestamp + 2 hours);
        uint256 bal3 = rebaseToken.balanceOf(TEST_USER_1);

        // Due to truncation, the diff will always have a small, like 1 wei difference caused by precision factor during
        // division.
        // Thus this will not work
        // assertEq(bal2 - bal1, bal3 - bal2);
        // Then we use the `assertApproxEqAbs` cheatcode
        assertApproxEqAbs(bal2 - bal1, bal3 - bal2, 1);
    }

    function testFuzz_redeem_UsersCanDepositAndRedeemImmediately(uint256 _amount) public {
        _amount = bound(_amount, 5e17, type(uint96).max);
        vm.deal(TEST_USER_1, _amount);

        vm.startPrank(TEST_USER_1);
        vault.deposit{value: _amount}();

        assertEq(rebaseToken.balanceOf(TEST_USER_1), _amount);
        assertEq(address(TEST_USER_1).balance, 0);

        // Withdraw all our deposit by passing the uint256 max
        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(TEST_USER_1), 0);
        assertEq(address(TEST_USER_1).balance, _amount);
        vm.stopPrank();
    }

    function testFuzz_redeem_UsersCanDepositAndRedeemAfterSomeTime(uint256 amount, uint256 time) public {
        amount = bound(amount, 5e17, type(uint96).max);
        time = bound(time, 1000, 10_000 * 365 days); // 1000 seconds and 10000 years

        vm.prank(TEST_USER_1);
        vm.deal(TEST_USER_1, amount);
        vault.deposit{value: amount}();

        // simulate some time passing
        vm.warp(block.timestamp + time);

        // Interest has accrued
        uint256 balancePlusInterest = rebaseToken.balanceOf(TEST_USER_1);

        // Make sure vault has that amount of rewards for user to be able to redeem.
        // On Setup, 10 ether was added as rewards, lets add another minimum of the acrued interest
        uint256 rewardsToAdd = balancePlusInterest - amount;
        vm.deal(owner, rewardsToAdd);
        vm.prank(owner);
        addVaultRewards(rewardsToAdd);

        vm.prank(TEST_USER_1);
        vault.redeem(type(uint256).max);

        uint256 finalEthBalance = TEST_USER_1.balance;

        assertGt(finalEthBalance, amount);
        assertEq(rebaseToken.balanceOf(TEST_USER_1), 0);
        assertEq(finalEthBalance, balancePlusInterest);
    }

    function testFuzz_transfer_UsersCanDepositAndTransferTheirRBTTokens(uint256 amount, uint256 transferAmt) public {
        amount = bound(amount, 1 ether, type(uint96).max); // minimum deposit amount of 1 ether
        // Minimum transfer is 0.5 ether and the max is always 0,5 ether less of the deposited amount.
        transferAmt = bound(transferAmt, 5e17, amount - 5e17);

        vm.deal(TEST_USER_1, amount);
        vm.prank(TEST_USER_1);
        vault.deposit{value: amount}();

        // Mid assertions of state
        uint256 user1StartBal = rebaseToken.balanceOf(TEST_USER_1);
        uint256 user2StartBal = rebaseToken.balanceOf(TEST_USER_2);
        assertEq(user1StartBal, amount);
        assertEq(user2StartBal, 0);

        // Do transfer and also confirm interest rate is inherited despite owner setting a new lower rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10); // currently it is 0.00000005%. This sets to 0.00000004%

        vm.prank(TEST_USER_1);
        rebaseToken.transfer(TEST_USER_2, transferAmt);

        // Final assertions
        uint256 user1EndBal = rebaseToken.balanceOf(TEST_USER_1);
        uint256 user2EndBal = rebaseToken.balanceOf(TEST_USER_2);

        assertEq(user1EndBal, user1StartBal - transferAmt);
        assertEq(user2EndBal, transferAmt);
        assertEq(rebaseToken.getUserInterestRate(TEST_USER_1), rebaseToken.getUserInterestRate(TEST_USER_2));
        assertNotEq(rebaseToken.getUserInterestRate(TEST_USER_2), 4e10);
    }

    function test_Revert_WhenNonOwnerAttemptsToSetGlobalInterestRate(address user, uint256 newRate) public {
        vm.assume(user != owner);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        vm.prank(user);
        rebaseToken.setInterestRate(newRate);
    }

    function test_Revert_IfUserWithoutMintAndBurnRoleAttemptsToMintOrBurnRBTs(
        address user,
        address recipient,
        uint256 amount
    )
        public
    {
        vm.assume(user != address(vault));

        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.mint(recipient, amount);

        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.burn(recipient, amount);
    }

    // Helpers
    function addVaultRewards(uint256 _rewardsAmount) internal {
        payable(address(vault)).call{value: _rewardsAmount}("");
    }

}
