// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { PerformanceFixture } from "./BaroPerformanceEscrow.t.sol";
import { BaroPerformanceEscrow } from "../src/BaroPerformanceEscrow.sol";
import { BaroCampaignEscrow } from "../src/BaroCampaignEscrow.sol";
import { BaroReputationSBT } from "../src/BaroReputationSBT.sol";
import { TaxToken } from "./mocks/PerformanceActors.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";

/// @dev Full amount reaches the recipient, but a separate fee is debited from the sender.
contract SenderFeeToken is MockERC20 {
    address public taxedSender;

    function setTaxedSender(address sender) external {
        taxedSender = sender;
    }

    function _update(address from, address to, uint256 amount) internal override {
        super._update(from, to, amount);
        if (from != address(0) && from == taxedSender && to != address(0)) {
            super._update(from, address(0), amount / 10);
        }
    }
}

contract PerformanceTokenAccountingTest is PerformanceFixture {
    SenderFeeToken internal token;

    function setUp() public override {
        super.setUp();
        token = new SenderFeeToken();
        token.mint(owner, 100 ether);
        escrow.setRewardTokenSupported(address(token), true);
        vm.prank(owner);
        token.approve(address(escrow), type(uint256).max);
    }

    function fundedPair() internal returns (uint256 first, uint256 second) {
        BaroPerformanceEscrow.Terms memory t = terms();
        t.token = address(token);
        first = create(t);
        second = create(t);
        token.setTaxedSender(address(escrow));
    }

    function testSenderFeePayoutCannotSpendAnotherCampaignBudget() public {
        (uint256 id, uint256 other) = fundedPair();
        vm.warp(START);
        BaroPerformanceEscrow.ActionReceipt memory r = receipt(id);
        bytes memory sig = sign(r);
        vm.expectRevert(BaroPerformanceEscrow.UnsupportedTokenBehavior.selector);
        escrow.settle(r, sig);
        assertEq(token.balanceOf(address(escrow)), 20 ether);
        assertEq(token.balanceOf(channel), 0);
        assertEq(escrow.totalLiability(address(token)), 20 ether);
        assertEq(escrow.getCampaign(other).remainingBudget, 10 ether);
        assertFalse(escrow.usedEvidence(r.evidenceHash));
        assertFalse(escrow.rewardedUsers(id, user));
        token.setTaxedSender(address(0));
        escrow.settle(r, sig);
        assertEq(token.balanceOf(channel), 1 ether);
    }

    function testSenderFeeRefundRollsBackWithoutDrainingOtherCampaign() public {
        (uint256 id, uint256 other) = fundedPair();
        vm.warp(END);
        vm.prank(owner);
        vm.expectRevert(BaroPerformanceEscrow.UnsupportedTokenBehavior.selector);
        escrow.refund(id);
        assertEq(escrow.getCampaign(id).remainingBudget, 10 ether);
        assertEq(escrow.getCampaign(other).remainingBudget, 10 ether);
        assertEq(token.balanceOf(address(escrow)), 20 ether);
        token.setTaxedSender(address(0));
        vm.prank(owner);
        escrow.refund(id);
        assertEq(escrow.totalLiability(address(token)), 10 ether);
    }
}

contract LegacyTokenAccountingTest is Test {
    BaroCampaignEscrow internal escrow;
    SenderFeeToken internal token;
    uint256 internal constant KEY = 0xB0B;
    address internal owner = address(0x1111);
    address internal user = address(0xCAFE);

    function setUp() public {
        vm.warp(1_000_000);
        BaroReputationSBT reputation =
            new BaroReputationSBT(address(this), vm.addr(KEY), address(this), "");
        escrow = new BaroCampaignEscrow(address(this), vm.addr(KEY), reputation);
        reputation.grantRole(reputation.ESCROW_ROLE(), address(escrow));
        bytes32 creatorRole = escrow.CAMPAIGN_CREATOR_ROLE();
        vm.prank(vm.addr(KEY));
        escrow.grantRole(creatorRole, owner);
        token = new SenderFeeToken();
        token.mint(owner, 100 ether);
        escrow.setRewardTokenSupported(address(token), true);
        vm.prank(owner);
        token.approve(address(escrow), type(uint256).max);
    }

    function create() internal returns (uint256) {
        vm.prank(owner);
        return
            escrow.createCampaign(address(token), 10 ether, 1 ether, 2 ether, 1_000_100, 1_003_700);
    }

    function testSenderFeeQuestPayoutCannotConsumeOtherLiabilities() public {
        uint256 id = create();
        create();
        token.setTaxedSender(address(escrow));
        vm.warp(1_000_100);
        BaroCampaignEscrow.QuestClaim memory claim = BaroCampaignEscrow.QuestClaim({
            user: user,
            campaignId: id,
            questId: 1,
            rewardToken: address(token),
            amount: 1 ether,
            nonce: 1,
            deadline: 1_003_700
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(KEY, escrow.hashQuestClaim(claim));
        bytes memory sig = abi.encodePacked(r, s, v);
        vm.prank(user);
        vm.expectRevert(BaroCampaignEscrow.UnsupportedTokenBehavior.selector);
        escrow.claimReward(claim, vm.addr(KEY), sig);
        assertEq(token.balanceOf(address(escrow)), 20 ether);
        assertEq(escrow.totalLiability(address(token)), 20 ether);
        assertFalse(escrow.usedNonces(user, 1));
        assertFalse(escrow.claimedQuests(id, 1, user));
        token.setTaxedSender(address(0));
        vm.prank(user);
        escrow.claimReward(claim, vm.addr(KEY), sig);
        assertEq(token.balanceOf(user), 1 ether);
    }

    function testSenderFeeWithdrawalCannotDrainOtherCampaign() public {
        uint256 id = create();
        create();
        token.setTaxedSender(address(escrow));
        vm.prank(owner);
        escrow.deactivateCampaign(id);
        vm.warp(1_003_701);
        vm.prank(owner);
        vm.expectRevert(BaroCampaignEscrow.UnsupportedTokenBehavior.selector);
        escrow.withdrawRemainingBudget(id);
        assertEq(token.balanceOf(address(escrow)), 20 ether);
        assertEq(escrow.totalLiability(address(token)), 20 ether);
        token.setTaxedSender(address(0));
        vm.prank(owner);
        escrow.withdrawRemainingBudget(id);
        assertEq(escrow.totalLiability(address(token)), 10 ether);
    }

    function testSenderFeeExcessRecoveryCannotSpendLiability() public {
        create();
        token.mint(address(escrow), 1 ether);
        token.setTaxedSender(address(escrow));
        vm.expectRevert(BaroCampaignEscrow.UnsupportedTokenBehavior.selector);
        escrow.recoverExcessBalance(address(token), payable(address(0xBEEF)), 1 ether);
        assertEq(token.balanceOf(address(escrow)), 11 ether);
        assertEq(escrow.totalLiability(address(token)), 10 ether);
        token.setTaxedSender(address(0));
        escrow.recoverExcessBalance(address(token), payable(address(0xBEEF)), 1 ether);
        assertEq(token.balanceOf(address(escrow)), 10 ether);
    }

    function testRecipientFeeOutputsRollBackAllLegacyAccounting() public {
        TaxToken taxed = new TaxToken();
        taxed.mint(owner, 10 ether);
        escrow.setRewardTokenSupported(address(taxed), true);
        vm.prank(owner);
        taxed.approve(address(escrow), 10 ether);
        vm.prank(owner);
        uint256 id =
            escrow.createCampaign(address(taxed), 10 ether, 1 ether, 2 ether, 1_000_100, 1_003_700);
        taxed.setTax(true);
        vm.warp(1_000_100);
        BaroCampaignEscrow.QuestClaim memory claim = BaroCampaignEscrow.QuestClaim({
            user: user,
            campaignId: id,
            questId: 1,
            rewardToken: address(taxed),
            amount: 1 ether,
            nonce: 1,
            deadline: 1_003_700
        });
        (uint8 v, bytes32 r, bytes32 sigS) = vm.sign(KEY, escrow.hashQuestClaim(claim));
        bytes memory sig = abi.encodePacked(r, sigS, v);
        vm.prank(user);
        vm.expectRevert(BaroCampaignEscrow.UnsupportedTokenBehavior.selector);
        escrow.claimReward(claim, vm.addr(KEY), sig);
        assertFalse(escrow.usedNonces(user, 1));
        assertEq(taxed.balanceOf(user), 0);
        vm.prank(owner);
        escrow.deactivateCampaign(id);
        vm.warp(1_003_701);
        vm.prank(owner);
        vm.expectRevert(BaroCampaignEscrow.UnsupportedTokenBehavior.selector);
        escrow.withdrawRemainingBudget(id);
        assertEq(escrow.totalLiability(address(taxed)), 10 ether);
        taxed.mint(address(escrow), 1 ether);
        vm.expectRevert(BaroCampaignEscrow.UnsupportedTokenBehavior.selector);
        escrow.recoverExcessBalance(address(taxed), payable(address(0xBEEF)), 1 ether);
        assertEq(taxed.balanceOf(address(escrow)), 11 ether);
        taxed.setTax(false);
        vm.prank(owner);
        escrow.withdrawRemainingBudget(id);
        assertEq(taxed.balanceOf(owner), 10 ether);
        assertEq(escrow.totalLiability(address(taxed)), 0);
    }
}
