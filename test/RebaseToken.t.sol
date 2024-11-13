// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {console, Test} from "forge-std/Test.sol";

import {SourceRebaseToken} from "../src/SourceRebaseToken.sol";
import {Vault} from "../src/Vault.sol";

import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    SourceRebaseToken public rebaseToken;
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
        rebaseToken = new SourceRebaseToken(address(0), address(0)); // we are not sending anything cross-chain so no need to set the router and link contracts
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        sourcePool = makeAddr("pool");
        rebaseToken.setVaultAndPool(address(vault), address(sourcePool));
        vm.stopPrank();
    }

    function testDeposit() public {
        // Deposit funds
        vm.startPrank(user);
        vm.deal(user, SEND_VALUE);
        vault.deposit{value: SEND_VALUE}();

        console.log("block number: %d", block.number);
        console.log("block timestamp: %d", block.timestamp);
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("User start balance: %d", startBalance);
        console.log("accumulated interest: %d", rebaseToken.getAccumulatedInterestSinceLastUpdate(user));
        assertEq(startBalance, SEND_VALUE);

        // check the balance has increased after some time has passed
        vm.warp(101);
        vm.roll(101);

        console.log("block number: %d", block.number);
        console.log("block timestamp: %d", block.timestamp);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        console.log("User middle balance: %d", middleBalance);
        console.log("accumulated interest: %d", rebaseToken.getAccumulatedInterestSinceLastUpdate(user));

        //assertGt(middleBalance, startBalance);

        // check the balance has increased after some time has passed
        vm.warp(201);
        vm.roll(201);

        console.log("block number: %d", block.number);
        console.log("block timestamp: %d", block.timestamp);
        uint256 endBalance = rebaseToken.balanceOf(user);
        console.log("User end balance: %d", endBalance);
        console.log("accumulated interest: %d", rebaseToken.getAccumulatedInterestSinceLastUpdate(user));

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

    function testRedeemAfterTimeHasPassed() public {
        // Deposit funds
        vm.deal(user, SEND_VALUE);
        vm.prank(user);
        vault.deposit{value: SEND_VALUE}();

        // check the balance has increased after some time has passed
        vm.warp(101);
        vm.roll(101);

        // Add rewards to the vault
        vm.deal(owner, 1 ether);
        vm.prank(owner);
        addRewardsToVault(1 ether);

        // Redeem funds
        uint256 balance = rebaseToken.balanceOf(user);
        vm.prank(user);
        vault.redeem(balance);

        uint256 ethBalance = address(user).balance;

        assertEq(balance, ethBalance);
    }

    function testGetUserAccumulatedRate() public {
        // Deposit funds
        vm.startPrank(user);
        vm.deal(user, SEND_VALUE);
        vault.deposit{value: SEND_VALUE}();
        // Get user index
        uint256 userAccumulatedRate = rebaseToken.getUserAccumulatedRate(user);
        console.log("User index: %d", userAccumulatedRate);
        assertEq(userAccumulatedRate, 1e18);
        vm.stopPrank();
    }

    function testCannotDepositMoreThanMax() public {
        // Deposit funds
        vm.startPrank(user);
        vm.deal(user, 1e6);
        vm.expectRevert();
        vault.deposit{value: 1e6}();
        vm.stopPrank();
    }

    function testCannotCallMint() public {
        // Deposit funds
        vm.startPrank(user);
        vm.expectRevert();
        rebaseToken.mint(user, SEND_VALUE);
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

    // NOTE: do I even need to add this check?
    // function testCannotBurnZero() public {
    //     // Deposit funds
    //     vm.startPrank(user);
    //     vm.expectRevert();
    //     vault.redeem(0);
    //     vm.stopPrank();
    // }
}
