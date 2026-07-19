// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Cheoma} from "../src/Cheoma.sol";

contract CheomaTest is Test {
    Cheoma jip;
    address fund = makeAddr("roofFund");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    event TileLaid(uint256 indexed id, address indexed giver, uint24 color, string wish, uint256 donation);
    event RoofMilestone(uint256 count);

    function setUp() public {
        jip = new Cheoma(fund);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function test_layTile_storesTileAndMintsNft() public {
        vm.prank(alice);
        jip.layTile(77, 0x1fb6a3, "May the roof shelter everyone");

        Cheoma.Tile memory t = jip.tileOf(77);
        assertEq(t.giver, alice);
        assertEq(t.color, uint24(0x1fb6a3));
        assertEq(t.wish, "May the roof shelter everyone");
        assertEq(jip.ownerOf(77), alice);
        assertEq(jip.balanceOf(alice), 1);
        assertEq(jip.laidCount(), 1);
    }

    function test_layTile_emitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit TileLaid(5, alice, 0xff0000, "hi", 0);
        vm.prank(alice);
        jip.layTile(5, 0xff0000, "hi");
    }

    function test_layTile_revertsWhenTaken() public {
        vm.prank(alice);
        jip.layTile(1, 0x111111, "first");
        vm.prank(bob);
        vm.expectRevert("tile taken");
        jip.layTile(1, 0x222222, "second");
    }

    function test_layTile_revertsOffRoof() public {
        uint256 total = jip.TOTAL_TILES();
        vm.prank(alice);
        vm.expectRevert("off the roof");
        jip.layTile(total, 0x111111, "too far");
    }

    function test_layTile_revertsLongWish() public {
        bytes memory long = new bytes(141);
        for (uint256 i; i < 141; ++i) long[i] = "a";
        vm.prank(alice);
        vm.expectRevert("wish too long");
        jip.layTile(2, 0x111111, string(long));
    }

    function test_layTile_walletCap() public {
        vm.startPrank(alice);
        for (uint256 i; i < jip.MAX_PER_WALLET(); ++i) {
            jip.layTile(i, 0xabcdef, "tile");
        }
        vm.expectRevert("wallet cap");
        jip.layTile(99, 0xabcdef, "one too many");
        vm.stopPrank();
    }

    function test_donationForwardedToFund() public {
        vm.prank(alice);
        jip.layTile(10, 0x00ff00, "for the fund");
        vm.prank(bob);
        jip.layTile{value: 1 ether}(11, 0x0000ff, "with love");
        assertEq(fund.balance, 1 ether);
        assertEq(address(jip).balance, 0);
    }

    function test_milestoneEvent() public {
        uint256 m = jip.MILESTONE();
        // lay m-1 tiles from distinct wallets (cap is 16 per wallet)
        uint256 laid;
        for (uint256 w; laid < m - 1; ++w) {
            address giver = address(uint160(0xBEEF00 + w));
            vm.startPrank(giver);
            for (uint256 i; i < 16 && laid < m - 1; ++i) {
                jip.layTile(laid, 0x777777, "");
                ++laid;
            }
            vm.stopPrank();
        }
        vm.expectEmit(false, false, false, true);
        emit RoofMilestone(m);
        vm.prank(alice);
        jip.layTile(laid, 0x777777, "milestone!");
    }

    function test_getRange() public {
        vm.prank(alice);
        jip.layTile(3, 0xaabbcc, "range me");
        (address[] memory givers, uint24[] memory colors) = jip.getRange(0, 8);
        assertEq(givers[3], alice);
        assertEq(colors[3], uint24(0xaabbcc));
        assertEq(givers[0], address(0));
    }

    function test_transferKeepsGiver() public {
        vm.prank(alice);
        jip.layTile(42, 0x123456, "moving on");
        vm.prank(alice);
        jip.transferFrom(alice, bob, 42);
        assertEq(jip.ownerOf(42), bob);
        assertEq(jip.tileOf(42).giver, alice); // original donor preserved
    }

    function test_transferRequiresApproval() public {
        vm.prank(alice);
        jip.layTile(42, 0x123456, "mine");
        vm.prank(bob);
        vm.expectRevert("not allowed");
        jip.transferFrom(alice, bob, 42);
    }

    function test_tokenURI_isOnchainJson() public {
        vm.prank(alice);
        jip.layTile(0, 0xff00aa, 'a "quoted" wish');
        string memory uri = jip.tokenURI(0);
        assertTrue(bytes(uri).length > 100);
        assertEq(_slice(uri, 0, 29), "data:application/json;base64,");
    }

    function test_tileSVG_containsColor() public {
        vm.prank(alice);
        jip.layTile(9, 0xff00aa, "svg");
        string memory svg = jip.tileSVG(9);
        assertTrue(_contains(svg, "#ff00aa"));
        assertTrue(_contains(svg, "<svg"));
    }

    function test_coordinates() public view {
        (uint256 x, uint256 y) = jip.coordinates(65);
        assertEq(x, 1);
        assertEq(y, 1);
    }

    // ------------------------------------------------------------- helpers --
    function _slice(string memory s, uint256 start, uint256 len) private pure returns (string memory) {
        bytes memory b = bytes(s);
        bytes memory out = new bytes(len);
        for (uint256 i; i < len; ++i) out[i] = b[start + i];
        return string(out);
    }

    function _contains(string memory hay, string memory needle) private pure returns (bool) {
        bytes memory h = bytes(hay);
        bytes memory n = bytes(needle);
        if (n.length > h.length) return false;
        for (uint256 i; i <= h.length - n.length; ++i) {
            bool ok = true;
            for (uint256 j; j < n.length; ++j) {
                if (h[i + j] != n[j]) { ok = false; break; }
            }
            if (ok) return true;
        }
        return false;
    }
}
