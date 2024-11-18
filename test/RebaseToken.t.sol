// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {console, Test} from "forge-std/Test.sol";

import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";

import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken public rebaseToken;
    Vault public vault;
    address public sourcePool; // don't really need this in this test but it's fine

    address public user = makeAddr("user");
    address public owner = makeAddr("owner");
    uint256 public SEND_VALUE = 1e5;

    function addRewardsToVault(uint256 amount) public {
        // send some rewards to the vault using the receive function
        payable(address(vault)).transfer(amount);
    }

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        sourcePool = makeAddr("pool");
        rebaseToken.grantRole(rebaseToken.MINT_AND_BURN_ROLE(), sourcePool);
        rebaseToken.grantRole(rebaseToken.MINT_AND_BURN_ROLE(), address(vault));
        vm.stopPrank();
    }

    function testDeposit() public {
        // Deposit funds
        vm.startPrank(user);
        vm.deal(user, SEND_VALUE);
        vault.deposit{value: SEND_VALUE}();

        console.log("block timestamp: %d", block.timestamp);
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("User start balance: %d", startBalance);
        assertEq(startBalance, SEND_VALUE);

        // check the balance has increased after 1 hour has passed
        vm.warp(block.timestamp + 1 hours);

        console.log("block timestamp: %d", block.timestamp);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        console.log("User middle balance: %d", middleBalance);

        //assertGt(middleBalance, startBalance);

        // check the balance has increased after 1 hour has passed
        vm.warp(block.timestamp + 1 hours);

        console.log("block timestamp: %d", block.timestamp);
        uint256 endBalance = rebaseToken.balanceOf(user);
        console.log("User end balance: %d", endBalance);

        assertGt(endBalance, middleBalance);

        uint256 differenceOne = middleBalance - startBalance;
        uint256 differenceTwo = endBalance - middleBalance;

        assertEq(differenceTwo, differenceOne);
        vm.stopPrank();
    }

    function testRedeemStraightAway() public {
        // Deposit funds
        vm.startPrank(user);
        vm.deal(user, SEND_VALUE);
        vault.deposit{value: SEND_VALUE}();

        // Redeem funds
        vault.redeem(SEND_VALUE);

        uint256 balance = rebaseToken.balanceOf(user);
        console.log("User balance: %d", balance);
        assertEq(balance, 0);
        vm.stopPrank();
    }

    function testRedeemAfterTimeHasPassed(uint256 depositAmount, uint256 time) public {
        vm.assume(depositAmount > 1e5);
        vm.assume(time > 100);
        depositAmount = bound(depositAmount, 1e5, type(uint96).max); // this is an Ether value of max 2^78 which is crazy
        time = bound(time, 100, type(uint96).max); // this is 2.5 * 10^21 years... so yeah if the fuzz test passes, we goooood

        // Deposit funds
        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();

        // check the balance has increased after some time has passed
        vm.warp(time);

        // Get balance after time has passed
        uint256 balance = rebaseToken.balanceOf(user);

        // Add rewards to the vault
        vm.deal(owner, balance - depositAmount);
        vm.prank(owner);
        addRewardsToVault(balance - depositAmount);

        // Redeem funds
        vm.prank(user);
        vault.redeem(balance);

        uint256 ethBalance = address(user).balance;

        assertEq(balance, ethBalance);
        assertGt(balance, depositAmount);
    }

    function testCannotCallMint() public {
        // Deposit funds
        vm.startPrank(user);
        uint256 interestRate = rebaseToken.getInterestRate();
        vm.expectRevert();
        rebaseToken.mint(user, SEND_VALUE, interestRate);
        vm.stopPrank();
    }

    function testCannotCallBurn() public {
        // Deposit funds
        vm.startPrank(user);
        vm.expectRevert();
        rebaseToken.burn(user, SEND_VALUE);
        vm.stopPrank();
    }

    function testCannotWithdrawMoreThanBalance() public {
        // Deposit funds
        vm.startPrank(user);
        vm.deal(user, SEND_VALUE);
        vault.deposit{value: SEND_VALUE}();
        vm.expectRevert();
        vault.redeem(SEND_VALUE + 1);
        vm.stopPrank();
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        // Deposit funds
        //uint256 amount = 1e5;
        //uint256 amountToSend = 5e4;
        // do this assume to avoid overflow
        vm.assume(amount < type(uint96).max);
        vm.assume(amountToSend < type(uint96).max);
        vm.assume(amount >= 1e3 + amountToSend);
        vm.assume(amountToSend > 1e3);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        // Send half the balance to another user
        address userTwo = makeAddr("userTwo");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 userTwoBalance = rebaseToken.balanceOf(userTwo);

        vm.prank(user);
        rebaseToken.transfer(userTwo, amountToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 userTwoBalancAfterTransfer = rebaseToken.balanceOf(userTwo);
        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(userTwoBalancAfterTransfer, userTwoBalance + amountToSend);
        // After some time has passed, check the balance of the two users has increased
        vm.warp(100000);
        uint256 userBalanceAfterWarp = rebaseToken.balanceOf(user);
        uint256 userTwoBalanceAfterWarp = rebaseToken.balanceOf(userTwo);
        // uint256 userAccumulatedInterestAfterWarp = rebaseToken.getUserAccumulatedInterest(user);
        // uint256 userTwoAccumulatedInterestAfterWarp = rebaseToken.getUserAccumulatedInterest(userTwo);
        // console.log("User accumulated interest after warp: %d", userAccumulatedInterestAfterWarp);
        // console.log("User two accumulated interest after warp: %d", userTwoAccumulatedInterestAfterWarp);
        assertGt(userBalanceAfterWarp, userBalanceAfterTransfer);
        assertGt(userTwoBalanceAfterWarp, userTwoBalancAfterTransfer);
    }
}
