// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {BriefsToken} from "src/BriefsToken.sol";

/// @notice Boundary and algebraic properties complement the existing ERC-20 examples.
/// forge-config: default.fuzz.runs = 1000
contract BriefsTokenPropertiesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;

    BriefsToken private token;
    address private alice;
    address private bob;
    address private spender;
    address private otherSpender;

    function setUp() public {
        token = new BriefsToken();
        alice = makeAddr("properties alice");
        bob = makeAddr("properties bob");
        spender = makeAddr("properties spender");
        otherSpender = makeAddr("properties other spender");
    }

    function test_oneWeiCanBeApprovedSpentAndReturned() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, spender), 0);

        vm.prank(bob);
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumAmountCannotBypassBalanceOrAllowanceChecks() public {
        uint256 maximum = type(uint256).max;
        bytes memory insufficientBalance =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, maximum);

        vm.expectRevert(insufficientBalance);
        token.transfer(alice, maximum);

        assertTrue(token.approve(spender, maximum));
        vm.expectRevert(insufficientBalance);
        vm.prank(spender);
        token.transferFrom(address(this), alice, maximum);
        assertEq(token.allowance(address(this), spender), maximum);

        assertTrue(token.approve(spender, maximum - 1));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, maximum - 1, maximum)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, maximum);
        assertEq(token.allowance(address(this), spender), maximum - 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_largestFiniteAllowanceIsSpentAcrossRepeatedTransfers() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);

        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY - 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_unlimitedApprovalCanBeReducedAndRevoked() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 2));
        assertEq(token.allowance(address(this), spender), 0);
        _expectNoAllowance();

        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 0));
        _expectNoAllowance();
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
        assertEq(token.balanceOf(alice), 3);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_refundingTokensDoesNotRestoreSpentApproval() public {
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));

        _expectNoAllowance();
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroValueTransfersPreserveFiniteAndInfiniteApprovals() public {
        assertTrue(token.approve(spender, 1));
        assertTrue(token.approve(otherSpender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 0));
        vm.prank(otherSpender);
        assertTrue(token.transferFrom(address(this), alice, 0));

        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.allowance(address(this), otherSpender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroApprovalToZeroSpenderStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_zeroValueDelegatedTransferStillRejectsZeroReceiver() public {
        // A zero amount needs no allowance, but it must still validate the receiver.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_failedDelegatedSelfTransferDoesNotConsumeApproval() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 2));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(spender);
        token.transferFrom(alice, alice, 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.allowance(alice, spender), 2);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_tokenContractCanReceiveTokensWithoutChangingSupply() public {
        // Receiving its own ERC-20 is an ordinary balance credit, not a burn.
        assertTrue(token.transfer(address(token), 1));
        assertTrue(token.approve(spender, SUPPLY - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(token), SUPPLY - 1));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedTransferFromPreservesApprovalAndAllowsRetry(
        uint256 balance,
        uint256 excess,
        uint256 approved
    ) public {
        balance = bound(balance, 0, SUPPLY);
        uint256 attempted = balance + bound(excess, 1, type(uint256).max - balance);
        approved = bound(approved, attempted, type(uint256).max);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, attempted)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, attempted);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, balance));
        assertEq(token.allowance(alice, spender), approved == type(uint256).max ? approved : approved - balance);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), balance);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_invalidReceiverPreservesApprovalAndAllowsRetry(uint256 amount, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, amount));
        assertEq(token.allowance(address(this), spender), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalsAreIndependentAndIdempotent(uint256 first, uint256 second, uint256 replacement) public {
        assertTrue(token.approve(spender, first));
        assertTrue(token.approve(otherSpender, second));
        vm.prank(alice);
        assertTrue(token.approve(spender, first));

        assertTrue(token.approve(spender, replacement));
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.allowance(address(this), otherSpender), second);
        assertEq(token.allowance(alice, spender), first);
        assertEq(token.allowance(alice, otherSpender), 0);

        assertTrue(token.approve(spender, 0));
        _expectNoAllowance();
        assertEq(token.allowance(address(this), otherSpender), second);
        assertEq(token.allowance(alice, spender), first);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splitTransfersMatchCombinedTransferAndRoundTrip(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        BriefsToken combined = new BriefsToken();
        assertTrue(token.approve(spender, type(uint256).max - 1));

        assertTrue(token.transfer(alice, first));
        assertTrue(token.transfer(alice, second));
        assertTrue(combined.transfer(alice, first + second));
        assertEq(token.balanceOf(alice), first + second);
        assertEq(token.balanceOf(alice), combined.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), combined.balanceOf(address(this)));

        vm.prank(alice);
        assertTrue(token.transfer(address(this), first + second));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(combined.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedSelfTransferChangesOnlyAllowance(uint256 balance, uint256 amount, uint256 approved)
        public
    {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, 0, balance);
        approved = bound(approved, amount, type(uint256).max);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, amount));
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(alice, spender), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transactionOriginCannotUseAnApproval(uint256 amount) public {
        amount = bound(amount, 1, SUPPLY);
        assertTrue(token.approve(spender, amount));

        // Even when the approved spender originated the transaction, an intermediary
        // calling the token needs an allowance of its own.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, amount));
        vm.prank(bob, spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);

        vm.prank(spender, bob);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _expectNoAllowance() private {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
    }
}
