// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {RebaseToken} from "../../src/RebaseToken.sol";
import {Vault} from "../../src/Vault.sol";
import {IRebaseToken} from "../../src/interfaces/IRebaseToken.sol";
import {Test, console} from "forge-std/Test.sol";

contract RebaseTokenUnitTest is Test {

    RebaseToken rebaseToken;
    Vault vault;

    address owner = makeAddr("deployer_or_owner");
    address TEST_USER_1 = makeAddr("Test User 1");

    function setUp() public {
        vm.label(TEST_USER_1, "TEST_USER_1");
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

}
