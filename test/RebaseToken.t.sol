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
        payable(address(vault)).call{value: amount}("");
    }

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        sourcePool = makeAddr("pool");
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function testDepositLinear() public {
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

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        // Deposit funds
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        // Redeem funds
        vault.redeem(amount);

        uint256 balance = rebaseToken.balanceOf(user);
        console.log("User balance: %d", balance);
        assertEq(balance, 0);
        vm.stopPrank();
    }

    function testRedeemAfterTimeHasPassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max); // this is a crazy number of years - 2^96 seconds is a lot
        depositAmount = bound(depositAmount, 1e5, type(uint96).max); // this is an Ether value of max 2^78 which is crazy

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

    function testDeposit(uint256 amount) public {
        amount = bound(amount, 1e3, type(uint96).max);
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e3, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e3);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address userTwo = makeAddr("userTwo");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 userTwoBalance = rebaseToken.balanceOf(userTwo);
        assertEq(userBalance, amount);
        assertEq(userTwoBalance, 0);

        // Update the interest rate so we can check the user interest rates are different after transferring.
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // Send half the balance to another user
        vm.prank(user);
        rebaseToken.transfer(userTwo, amountToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 userTwoBalancAfterTransfer = rebaseToken.balanceOf(userTwo);
        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(userTwoBalancAfterTransfer, userTwoBalance + amountToSend);
        // After some time has passed, check the balance of the two users has increased
        vm.warp(block.timestamp + 1 days);
        uint256 userBalanceAfterWarp = rebaseToken.balanceOf(user);
        uint256 userTwoBalanceAfterWarp = rebaseToken.balanceOf(userTwo);
        // check their interest rates are as expected
        // since user two hadn't minted before, their interest rate should be the same as in the contract
        uint256 userTwoInterestRate = rebaseToken.getUserInterestRate(userTwo);
        assertEq(userTwoInterestRate, 5e10);
        // since user had minted before, their interest rate should be the previous interest rate
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        assertEq(userInterestRate, 5e10);

        assertGt(userBalanceAfterWarp, userBalanceAfterTransfer);
        assertGt(userTwoBalanceAfterWarp, userTwoBalancAfterTransfer);
    }

    function testSetInterestRate(uint256 newInterestRate) public {
        // bound the interest rate to be less than the current interest rate
        newInterestRate = bound(newInterestRate, 0, rebaseToken.getInterestRate());
        // Update the interest rate
        vm.startPrank(owner);
        rebaseToken.setInterestRate(newInterestRate);
        uint256 interestRate = rebaseToken.getInterestRate();
        assertEq(interestRate, newInterestRate);
        vm.stopPrank();

        // check that if someone deposits, this is their new interest rate
        vm.startPrank(user);
        vm.deal(user, SEND_VALUE);
        vault.deposit{value: SEND_VALUE}();
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        vm.stopPrank();
        assertEq(userInterestRate, newInterestRate);
    }

    function testCannotSetInterestRate(uint256 newInterestRate) public {
        // Update the interest rate
        vm.startPrank(user);
        vm.expectRevert();
        rebaseToken.setInterestRate(newInterestRate);
        vm.stopPrank();
    }

    function testInterestRateDoesntUpdateIfMoreThanPreviousRate(uint256 newInterestRate) public {
        // make sure the new interest rate is less than the previous interest rate
        newInterestRate = bound(newInterestRate, rebaseToken.getInterestRate() + 1, type(uint96).max);
        vm.prank(owner);

        rebaseToken.setInterestRate(newInterestRate);
        uint256 interestRate = rebaseToken.getInterestRate();
        assertNotEq(interestRate, newInterestRate);
    }

    function testGetPrincipleAmount() public {
        uint256 amount = 1e5;
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        uint256 principleAmount = rebaseToken.principalBalanceOf(user);
        assertEq(principleAmount, amount);

        // check that the principle amount is the same after some time has passed
        vm.warp(block.timestamp + 1 days);
        uint256 principleAmountAfterWarp = rebaseToken.principalBalanceOf(user);
        assertEq(principleAmountAfterWarp, amount);
    }
}
