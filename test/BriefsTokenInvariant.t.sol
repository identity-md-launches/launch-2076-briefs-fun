// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {BriefsToken} from "../src/BriefsToken.sol";

/// @dev A closed set of holders and a separate ledger model exercise arbitrary operation sequences.
contract BriefsTokenHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    BriefsToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new BriefsToken();
        actors[0] = address(this);
        actors[1] = makeAddr("invariant alice");
        actors[2] = makeAddr("invariant bob");
        actors[3] = makeAddr("invariant carol");
        expectedBalance[address(this)] = SUPPLY;

        // Fund every actor through real transfers so delegated calls need not wait for
        // a rare sequence of funding and approval operations to move a nonzero amount.
        for (uint256 i = 1; i < actors.length; ++i) {
            assertTrue(token.transfer(actors[i], SUPPLY / 4));
            expectedBalance[address(this)] -= SUPPLY / 4;
            expectedBalance[actors[i]] = SUPPLY / 4;
        }
        for (uint256 i; i < actors.length; ++i) {
            address owner = actors[i];
            address spender = actors[(i + 1) % actors.length];
            vm.prank(owner);
            assertTrue(token.approve(spender, SUPPLY / 4));
            expectedAllowance[owner][spender] = SUPPLY / 4;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Finite approvals may exceed the entire supply, including uint256.max - 1.
        amount = unlimited ? type(uint256).max : bound(amount, 0, type(uint256).max - 1);

        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 available = expectedAllowance[owner][spender];
        uint256 limit = expectedBalance[owner] < available ? expectedBalance[owner] : available;
        amount = bound(amount, 0, limit);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (available != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }

    function rejectOverspend(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[from] + 1;

        vm.prank(from);
        (bool success, bytes memory reason) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        assertFalse(success, "overspend succeeded");
        assertEq(
            reason,
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, expectedBalance[from], amount)
        );
    }

    function rejectExcessAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 available = expectedAllowance[owner][spender];
        if (available == type(uint256).max) return;

        vm.prank(spender);
        (bool success, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, to, available + 1)));
        assertFalse(success, "allowance overrun succeeded");
        assertEq(
            reason,
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, available, available + 1)
        );
    }

    function transferAll(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[from];

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
    }

    function rejectTransferToZero(uint256 fromSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        (bool success, bytes memory reason) = address(token).call(abi.encodeCall(token.transfer, (address(0), amount)));
        assertFalse(success, "transfer to zero succeeded");
        assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
    }

    function rejectApprovalToZero(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.prank(owner);
        (bool success, bytes memory reason) = address(token).call(abi.encodeCall(token.approve, (address(0), amount)));
        assertFalse(success, "approval to zero succeeded");
        assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
    }

    function rejectTransferFromToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 available = expectedAllowance[owner][spender];
        uint256 limit = expectedBalance[owner] < available ? expectedBalance[owner] : available;
        amount = bound(amount, 0, limit);

        vm.prank(spender);
        (bool success, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, address(0), amount)));
        assertFalse(success, "delegated transfer to zero succeeded");
        assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        // Keep the ghost allowance unchanged: the attempted spend must roll back.
    }

    function rejectTransferFromOverBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 excess,
        bool unlimited
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 amount = balance + bound(excess, 1, type(uint256).max - balance);
        uint256 approved = unlimited ? type(uint256).max : amount;

        // Make allowance sufficient so the failure actually reaches the balance check.
        vm.prank(owner);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[owner][spender] = approved;

        vm.prank(spender);
        (bool success, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, to, amount)));
        assertFalse(success, "delegated overspend succeeded");
        assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
    }
}

/// @dev Unexpected handler reverts must fail the campaign, including assertion failures.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract BriefsTokenInvariantTest is StdInvariant, Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    BriefsTokenHandler private handler;
    BriefsToken private token;

    function setUp() public {
        handler = new BriefsTokenHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.rejectOverspend.selector;
        selectors[4] = handler.rejectExcessAllowance.selector;
        selectors[5] = handler.transferAll.selector;
        selectors[6] = handler.revoke.selector;
        selectors[7] = handler.rejectTransferToZero.selector;
        selectors[8] = handler.rejectApprovalToZero.selector;
        selectors[9] = handler.rejectTransferFromToZero.selector;
        selectors[10] = handler.rejectTransferFromOverBalance.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyAndBalancesMatchIndependentLedger() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_allowancesMatchIndependentLedger() public view {
        for (uint256 i; i < 4; ++i) {
            assertEq(token.allowance(handler.actors(i), address(0)), 0);
            assertEq(token.allowance(address(0), handler.actors(i)), 0);
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    /// @dev Every holder can still move its entire balance after an arbitrary history,
    /// including after revoked approvals and failed delegated transfers.
    function afterInvariant() public {
        for (uint256 i = 1; i < 4; ++i) {
            handler.transferAll(i, 0);
        }
        assertEq(token.balanceOf(address(handler)), SUPPLY);
        invariant_supplyAndBalancesMatchIndependentLedger();
        invariant_allowancesMatchIndependentLedger();
    }
}
