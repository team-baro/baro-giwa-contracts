// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";

import { BaroReputationSBT } from "../src/BaroReputationSBT.sol";

contract BaroReputationSBTTest is Test {
    address private admin = makeAddr("admin");
    address private operator = makeAddr("operator");
    address private escrow = makeAddr("escrow");
    address private user = makeAddr("user");
    address private recipient = makeAddr("recipient");

    BaroReputationSBT private reputation;

    function setUp() external {
        reputation = new BaroReputationSBT(admin, operator, escrow, "https://api.baro.quest/sbt/");
    }

    function testMintsOneTokenAndTracksDistinctCampaigns() external {
        vm.startPrank(escrow);
        reputation.recordQuestCompletion(user, 1);
        reputation.recordQuestCompletion(user, 1);
        reputation.recordQuestCompletion(user, 2);
        vm.stopPrank();

        assertEq(reputation.balanceOf(user), 1);
        (uint64 questCount, uint64 campaignCount,,,) = reputation.reputations(user);
        assertEq(questCount, 3);
        assertEq(campaignCount, 2);
    }

    function testTokenCannotBeTransferredOrApproved() external {
        vm.prank(escrow);
        reputation.recordQuestCompletion(user, 1);
        uint256 tokenId = reputation.tokenIds(user);

        vm.expectRevert(BaroReputationSBT.Soulbound.selector);
        vm.prank(user);
        reputation.transferFrom(user, recipient, tokenId);

        vm.expectRevert(BaroReputationSBT.Soulbound.selector);
        vm.prank(user);
        reputation.approve(recipient, tokenId);
    }

    function testOperatorCanVerifyChannel() external {
        vm.prank(operator);
        reputation.verifyChannel(user, 85);

        (,,, uint32 channelScore, bool verified) = reputation.reputations(user);
        assertEq(channelScore, 85);
        assertTrue(verified);
    }

    function testTokenURIUsesOperatorManagedBaseURI() external {
        vm.prank(escrow);
        reputation.recordQuestCompletion(user, 1);
        uint256 tokenId = reputation.tokenIds(user);
        assertEq(reputation.tokenURI(tokenId), "https://api.baro.quest/sbt/1");

        vm.prank(operator);
        reputation.setBaseURI("ipfs://baro/");
        assertEq(reputation.tokenURI(tokenId), "ipfs://baro/1");
    }

    function testRejectsUnauthorizedCompletion() external {
        vm.expectPartialRevert(
            bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"))
        );
        vm.prank(user);
        reputation.recordQuestCompletion(user, 1);
    }

    function testRejectsChannelScoreAboveOneHundred() external {
        vm.expectRevert(BaroReputationSBT.ScoreOutOfRange.selector);
        vm.prank(operator);
        reputation.verifyChannel(user, 101);
    }
}
