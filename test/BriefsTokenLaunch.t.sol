// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BriefsToken} from "../src/BriefsToken.sol";

/// @dev Test fixture only: represents the immediate CREATE2 deployer.
contract LaunchDeployerFixture {
    function deploy(bytes32 salt) external returns (BriefsToken) {
        return new BriefsToken{salt: salt}();
    }
}

contract BriefsTokenLaunchTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    LaunchDeployerFixture private factory;
    BriefsToken private token;
    address private launcher;
    address private distributor;
    address private poolManager;
    address private remainderRecipient;
    address private claimant;
    address private trader;

    function setUp() public {
        launcher = makeAddr("launch operator");
        distributor = makeAddr("distributor fixture");
        poolManager = makeAddr("pool manager fixture");
        remainderRecipient = makeAddr("remainder recipient fixture");
        claimant = makeAddr("claimant");
        trader = makeAddr("trader");
        factory = new LaunchDeployerFixture();

        vm.prank(launcher, launcher);
        token = factory.deploy(keccak256("Briefs.fun launch fixture"));
    }

    function test_factoryReceivesAllSupplyAndOriginReceivesNone() public view {
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(launcher), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_create2AddressMatchesConstructorWithoutArguments() public view {
        bytes32 digest = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(factory),
                keccak256("Briefs.fun launch fixture"),
                keccak256(type(BriefsToken).creationCode)
            )
        );
        // The CREATE2 address is the low 160 bits of the digest.
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(address(token), address(uint160(uint256(digest))));
    }

    function test_launchDistributionClaimsAndTradingTransfersAreExact() public {
        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY * 80 / 100;
        uint256 remainder = SUPPLY - swarmShare - poolShare;

        vm.startPrank(address(factory));
        assertTrue(token.transfer(distributor, swarmShare));
        assertTrue(token.transfer(poolManager, poolShare));
        assertTrue(token.transfer(remainderRecipient, remainder));
        vm.stopPrank();
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), swarmShare);
        assertEq(token.balanceOf(poolManager), poolShare);
        assertEq(token.balanceOf(remainderRecipient), remainder);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarmShare));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), swarmShare);

        // Exercise the token movements in both directions; this fixture is not an AMM.
        uint256 tradeAmount = 123_456 ether;
        vm.prank(poolManager);
        assertTrue(token.transfer(trader, tradeAmount));
        assertEq(token.balanceOf(trader), tradeAmount);
        assertEq(token.balanceOf(poolManager), poolShare - tradeAmount);
        vm.prank(trader);
        assertTrue(token.transfer(poolManager, tradeAmount));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(poolManager), poolShare);
        assertEq(token.balanceOf(claimant) + token.balanceOf(poolManager) + token.balanceOf(remainderRecipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_runtimeFitsDeploymentLimitAndHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4, "DELEGATECALL");
            assertTrue(opcode != 0xf2, "CALLCODE");
            assertTrue(opcode != 0xff, "SELFDESTRUCT");
        }
    }
}
