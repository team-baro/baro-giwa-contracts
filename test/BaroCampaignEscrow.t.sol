// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";

import { BaroCampaignEscrow } from "../src/BaroCampaignEscrow.sol";
import { BaroReputationSBT } from "../src/BaroReputationSBT.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";

contract BaroCampaignEscrowTest is Test {
    uint256 private constant OPERATOR_KEY = 0xB0B;

    address private admin = makeAddr("admin");
    address private operator = vm.addr(OPERATOR_KEY);
    address private projectOwner = makeAddr("projectOwner");
    address private user = makeAddr("user");

    BaroCampaignEscrow private escrow;
    BaroReputationSBT private reputation;
    MockERC20 private rewardToken;

    function setUp() external {
        vm.warp(1_000_000);
        reputation = new BaroReputationSBT(admin, operator);
        escrow = new BaroCampaignEscrow(admin, operator, reputation);
        rewardToken = new MockERC20();

        bytes32 escrowRole = reputation.ESCROW_ROLE();
        vm.prank(admin);
        reputation.grantRole(escrowRole, address(escrow));
    }

    function testClaimNativeRewardAndRecordReputation() external {
        uint256 campaignId = _createNativeCampaign(10 ether);
        BaroCampaignEscrow.QuestClaim memory claim = _claim(campaignId, address(0), 1 ether, 7);
        bytes memory signature = _sign(claim, OPERATOR_KEY);

        uint256 balanceBefore = user.balance;
        vm.prank(user);
        escrow.claimReward(claim, operator, signature);

        assertEq(user.balance, balanceBefore + 1 ether);
        assertTrue(escrow.usedNonces(user, 7));
        (uint64 questCount, uint64 campaignCount,,,) = reputation.reputations(user);
        assertEq(questCount, 1);
        assertEq(campaignCount, 1);
    }

    function testClaimERC20Reward() external {
        rewardToken.mint(projectOwner, 100 ether);
        vm.startPrank(projectOwner);
        rewardToken.approve(address(escrow), 100 ether);
        uint256 campaignId = escrow.createCampaign(
            address(rewardToken),
            100 ether,
            uint64(block.timestamp),
            uint64(block.timestamp + 1 days)
        );
        vm.stopPrank();

        BaroCampaignEscrow.QuestClaim memory claim =
            _claim(campaignId, address(rewardToken), 5 ether, 8);
        bytes memory signature = _sign(claim, OPERATOR_KEY);
        vm.prank(user);
        escrow.claimReward(claim, operator, signature);

        assertEq(rewardToken.balanceOf(user), 5 ether);
    }

    function testRejectsReplayedNonce() external {
        uint256 campaignId = _createNativeCampaign(10 ether);
        BaroCampaignEscrow.QuestClaim memory claim = _claim(campaignId, address(0), 1 ether, 9);
        bytes memory signature = _sign(claim, OPERATOR_KEY);

        vm.prank(user);
        escrow.claimReward(claim, operator, signature);

        vm.expectRevert(BaroCampaignEscrow.NonceAlreadyUsed.selector);
        vm.prank(user);
        escrow.claimReward(claim, operator, signature);
    }

    function testRejectsSecondClaimForSameQuestWithNewNonce() external {
        uint256 campaignId = _createNativeCampaign(10 ether);
        BaroCampaignEscrow.QuestClaim memory firstClaim =
            _claim(campaignId, address(0), 1 ether, 20);
        bytes memory firstSignature = _sign(firstClaim, OPERATOR_KEY);

        vm.prank(user);
        escrow.claimReward(firstClaim, operator, firstSignature);

        BaroCampaignEscrow.QuestClaim memory secondClaim =
            _claim(campaignId, address(0), 1 ether, 21);
        bytes memory secondSignature = _sign(secondClaim, OPERATOR_KEY);
        vm.expectRevert(BaroCampaignEscrow.QuestAlreadyClaimed.selector);
        vm.prank(user);
        escrow.claimReward(secondClaim, operator, secondSignature);
    }

    function testRejectsUnauthorizedSigner() external {
        uint256 attackerKey = 0xBAD;
        address attacker = vm.addr(attackerKey);
        uint256 campaignId = _createNativeCampaign(10 ether);
        BaroCampaignEscrow.QuestClaim memory claim = _claim(campaignId, address(0), 1 ether, 10);
        bytes memory signature = _sign(claim, attackerKey);

        vm.expectRevert(BaroCampaignEscrow.InvalidClaimSigner.selector);
        vm.prank(user);
        escrow.claimReward(claim, attacker, signature);
    }

    function testRejectsClaimDeadlineAfterCampaign() external {
        uint256 campaignId = _createNativeCampaign(10 ether);
        BaroCampaignEscrow.QuestClaim memory claim = _claim(campaignId, address(0), 1 ether, 11);
        claim.deadline = block.timestamp + 2 days;
        bytes memory signature = _sign(claim, OPERATOR_KEY);

        vm.expectRevert(BaroCampaignEscrow.ClaimDeadlineAfterCampaign.selector);
        vm.prank(user);
        escrow.claimReward(claim, operator, signature);
    }

    function testProjectOwnerWithdrawsAfterCampaign() external {
        uint256 campaignId = _createNativeCampaign(10 ether);
        vm.warp(block.timestamp + 1 days + 1);

        uint256 balanceBefore = projectOwner.balance;
        vm.prank(projectOwner);
        escrow.withdrawRemainingBudget(campaignId);

        assertEq(projectOwner.balance, balanceBefore + 10 ether);
    }

    function _createNativeCampaign(uint128 budget) private returns (uint256 campaignId) {
        vm.deal(projectOwner, budget);
        vm.prank(projectOwner);
        campaignId = escrow.createCampaign{ value: budget }(
            address(0), budget, uint64(block.timestamp), uint64(block.timestamp + 1 days)
        );
    }

    function _claim(uint256 campaignId, address token, uint256 amount, uint256 nonce)
        private
        view
        returns (BaroCampaignEscrow.QuestClaim memory)
    {
        return BaroCampaignEscrow.QuestClaim({
            user: user,
            campaignId: campaignId,
            questId: 42,
            rewardToken: token,
            amount: amount,
            nonce: nonce,
            deadline: block.timestamp + 1 hours
        });
    }

    function _sign(BaroCampaignEscrow.QuestClaim memory claim, uint256 signerKey)
        private
        view
        returns (bytes memory)
    {
        bytes32 digest = escrow.hashQuestClaim(claim);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
