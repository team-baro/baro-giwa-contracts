// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { BaroCampaignEscrow } from "../src/BaroCampaignEscrow.sol";
import { BaroReputationSBT } from "../src/BaroReputationSBT.sol";
import { MockERC20, NonReceiverWallet } from "./mocks/MockERC20.sol";

contract BaroCampaignEscrowTest is Test {
    using SafeCast for uint256;
    uint256 private constant OPERATOR_KEY = 0xB0B;
    uint128 private constant BUDGET = 10 ether;
    uint128 private constant MAX_REWARD = 2 ether;
    uint128 private constant MAX_REWARD_PER_USER = 4 ether;

    address private admin = makeAddr("admin");
    address private operator = vm.addr(OPERATOR_KEY);
    address private projectOwner = makeAddr("projectOwner");
    address private user = makeAddr("user");

    BaroCampaignEscrow private escrow;
    BaroReputationSBT private reputation;
    MockERC20 private rewardToken;

    function setUp() external {
        vm.warp(1_000_000);

        // Tests deploy the SBT first; its initial escrow role belongs to this harness.
        reputation =
            new BaroReputationSBT(admin, operator, address(this), "https://api.baro.quest/sbt/");
        escrow = new BaroCampaignEscrow(admin, operator, reputation);
        rewardToken = new MockERC20();

        bytes32 escrowRole = reputation.ESCROW_ROLE();
        vm.prank(admin);
        reputation.grantRole(escrowRole, address(escrow));

        bytes32 creatorRole = escrow.CAMPAIGN_CREATOR_ROLE();
        vm.prank(operator);
        escrow.grantRole(creatorRole, projectOwner);

        vm.prank(admin);
        escrow.setRewardTokenSupported(address(rewardToken), true);
    }

    function testClaimNativeRewardAndRecordReputation() external {
        uint256 campaignId = _createNativeCampaign(block.timestamp, block.timestamp + 1 days);
        BaroCampaignEscrow.QuestClaim memory claim = _claim(campaignId, address(0), 1 ether, 7);
        bytes memory signature = _sign(claim, OPERATOR_KEY);

        uint256 balanceBefore = user.balance;
        vm.prank(user);
        escrow.claimReward(claim, operator, signature);

        assertEq(user.balance, balanceBefore + 1 ether);
        assertTrue(escrow.usedNonces(user, 7));
        assertTrue(escrow.claimedQuests(campaignId, 42, user));
        (uint64 questPoints, uint64 questCount, uint64 campaignCount,,,) =
            reputation.reputations(user);
        assertEq(questPoints, 10);
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
            10 ether,
            20 ether,
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

    function testSmartContractWalletCanClaimWithoutERC721Receiver() external {
        NonReceiverWallet wallet = new NonReceiverWallet();
        uint256 campaignId = _createNativeCampaign(block.timestamp, block.timestamp + 1 days);
        BaroCampaignEscrow.QuestClaim memory claim =
            _claimFor(address(wallet), campaignId, address(0), 1 ether, 12);
        bytes memory signature = _sign(claim, OPERATOR_KEY);

        wallet.claim(escrow, claim, operator, signature);

        assertEq(address(wallet).balance, 1 ether);
        assertEq(reputation.balanceOf(address(wallet)), 1);
    }

    function testOnlyApprovedCreatorCanCreateCampaign() external {
        address unapproved = makeAddr("unapproved");
        vm.deal(unapproved, BUDGET);

        vm.expectPartialRevert(
            bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"))
        );
        vm.prank(unapproved);
        escrow.createCampaign{ value: BUDGET }(
            address(0),
            BUDGET,
            MAX_REWARD,
            MAX_REWARD_PER_USER,
            uint64(block.timestamp),
            uint64(block.timestamp + 1 days)
        );
    }

    function testOperatorCanApproveCampaignCreator() external {
        address approved = makeAddr("approved");
        bytes32 creatorRole = escrow.CAMPAIGN_CREATOR_ROLE();
        vm.prank(operator);
        escrow.grantRole(creatorRole, approved);

        vm.deal(approved, BUDGET);
        vm.prank(approved);
        uint256 campaignId = escrow.createCampaign{ value: BUDGET }(
            address(0),
            BUDGET,
            MAX_REWARD,
            MAX_REWARD_PER_USER,
            uint64(block.timestamp),
            uint64(block.timestamp + 1 days)
        );

        (address owner,,,,,,,,) = escrow.campaigns(campaignId);
        assertEq(owner, approved);
    }

    function testRejectsRewardAboveCampaignMaximum() external {
        uint256 campaignId = _createNativeCampaign(block.timestamp, block.timestamp + 1 days);
        BaroCampaignEscrow.QuestClaim memory claim =
            _claim(campaignId, address(0), MAX_REWARD + 1, 13);
        bytes memory signature = _sign(claim, OPERATOR_KEY);

        vm.expectRevert(BaroCampaignEscrow.RewardExceedsMaximum.selector);
        vm.prank(user);
        escrow.claimReward(claim, operator, signature);
    }

    function testRejectsReplayedNonce() external {
        uint256 campaignId = _createNativeCampaign(block.timestamp, block.timestamp + 1 days);
        BaroCampaignEscrow.QuestClaim memory claim = _claim(campaignId, address(0), 1 ether, 9);
        bytes memory signature = _sign(claim, OPERATOR_KEY);

        vm.prank(user);
        escrow.claimReward(claim, operator, signature);

        vm.expectRevert(BaroCampaignEscrow.NonceAlreadyUsed.selector);
        vm.prank(user);
        escrow.claimReward(claim, operator, signature);
    }

    function testRejectsSecondClaimForSameQuestWithNewNonce() external {
        uint256 campaignId = _createNativeCampaign(block.timestamp, block.timestamp + 1 days);
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
        uint256 campaignId = _createNativeCampaign(block.timestamp, block.timestamp + 1 days);
        BaroCampaignEscrow.QuestClaim memory claim = _claim(campaignId, address(0), 1 ether, 10);
        bytes memory signature = _sign(claim, attackerKey);

        vm.expectRevert(BaroCampaignEscrow.InvalidClaimSigner.selector);
        vm.prank(user);
        escrow.claimReward(claim, attacker, signature);
    }

    function testRejectsClaimDeadlineAfterCampaign() external {
        uint256 campaignId = _createNativeCampaign(block.timestamp, block.timestamp + 1 days);
        BaroCampaignEscrow.QuestClaim memory claim = _claim(campaignId, address(0), 1 ether, 11);
        claim.deadline = block.timestamp + 2 days;
        bytes memory signature = _sign(claim, OPERATOR_KEY);

        vm.expectRevert(BaroCampaignEscrow.ClaimDeadlineAfterCampaign.selector);
        vm.prank(user);
        escrow.claimReward(claim, operator, signature);
    }

    function testRejectsClaimBeforeCampaignStarts() external {
        uint256 campaignId =
            _createNativeCampaign(block.timestamp + 1 hours, block.timestamp + 1 days);
        BaroCampaignEscrow.QuestClaim memory claim = _claim(campaignId, address(0), 1 ether, 14);
        bytes memory signature = _sign(claim, OPERATOR_KEY);

        vm.expectRevert(BaroCampaignEscrow.CampaignNotStarted.selector);
        vm.prank(user);
        escrow.claimReward(claim, operator, signature);
    }

    function testRejectsExpiredClaim() external {
        uint256 campaignId = _createNativeCampaign(block.timestamp, block.timestamp + 1 days);
        BaroCampaignEscrow.QuestClaim memory claim = _claim(campaignId, address(0), 1 ether, 15);
        claim.deadline = block.timestamp;
        bytes memory signature = _sign(claim, OPERATOR_KEY);
        vm.warp(block.timestamp + 1);

        vm.expectRevert(BaroCampaignEscrow.ClaimExpired.selector);
        vm.prank(user);
        escrow.claimReward(claim, operator, signature);
    }

    function testPausedContractRejectsClaimsAndCreation() external {
        uint256 campaignId = _createNativeCampaign(block.timestamp, block.timestamp + 1 days);
        BaroCampaignEscrow.QuestClaim memory claim = _claim(campaignId, address(0), 1 ether, 16);
        bytes memory signature = _sign(claim, OPERATOR_KEY);
        vm.prank(admin);
        escrow.pause();

        vm.expectPartialRevert(bytes4(keccak256("EnforcedPause()")));
        vm.prank(user);
        escrow.claimReward(claim, operator, signature);

        vm.deal(projectOwner, 1 ether);
        vm.expectPartialRevert(bytes4(keccak256("EnforcedPause()")));
        vm.prank(projectOwner);
        escrow.createCampaign{ value: 1 ether }(
            address(0),
            1 ether,
            1 ether,
            1 ether,
            uint64(block.timestamp),
            uint64(block.timestamp + 1 days)
        );
    }

    function testProjectOwnerWithdrawsAfterCampaign() external {
        uint256 campaignId = _createNativeCampaign(block.timestamp, block.timestamp + 1 days);
        vm.prank(projectOwner);
        escrow.deactivateCampaign(campaignId);
        vm.warp(block.timestamp + 1 days + 1);

        uint256 balanceBefore = projectOwner.balance;
        vm.prank(projectOwner);
        escrow.withdrawRemainingBudget(campaignId);

        assertEq(projectOwner.balance, balanceBefore + BUDGET);
    }

    function testActiveCampaignCannotBeWithdrawnAfterEnd() external {
        uint256 campaignId = _createNativeCampaign(block.timestamp, block.timestamp + 1 days);
        vm.warp(block.timestamp + 1 days + 1);

        vm.expectRevert(BaroCampaignEscrow.CampaignStillActive.selector);
        vm.prank(projectOwner);
        escrow.withdrawRemainingBudget(campaignId);
    }

    function testRejectsClaimsAbovePerUserCampaignLimit() external {
        uint256 campaignId = _createNativeCampaign(block.timestamp, block.timestamp + 1 days);
        for (uint256 index = 0; index < 2; index++) {
            BaroCampaignEscrow.QuestClaim memory claim =
                _claimForQuest(user, campaignId, address(0), 2 ether, 40 + index, 100 + index);
            bytes memory signature = _sign(claim, OPERATOR_KEY);
            vm.prank(user);
            escrow.claimReward(claim, operator, signature);
        }

        BaroCampaignEscrow.QuestClaim memory excessClaim =
            _claimForQuest(user, campaignId, address(0), 1 ether, 42, 102);
        bytes memory excessSignature = _sign(excessClaim, OPERATOR_KEY);
        vm.expectRevert(BaroCampaignEscrow.UserRewardLimitExceeded.selector);
        vm.prank(user);
        escrow.claimReward(excessClaim, operator, excessSignature);
    }

    function testRewardClaimSucceedsWhenReputationUpdateFailsThenRetries() external {
        uint256 campaignId = _createNativeCampaign(block.timestamp, block.timestamp + 1 days);
        bytes32 escrowRole = reputation.ESCROW_ROLE();
        vm.prank(admin);
        reputation.revokeRole(escrowRole, address(escrow));

        BaroCampaignEscrow.QuestClaim memory claim = _claim(campaignId, address(0), 1 ether, 50);
        bytes memory signature = _sign(claim, OPERATOR_KEY);
        vm.prank(user);
        escrow.claimReward(claim, operator, signature);

        assertEq(user.balance, 1 ether);
        assertTrue(escrow.pendingReputationUpdates(campaignId, claim.questId, user));

        vm.prank(admin);
        reputation.grantRole(escrowRole, address(escrow));
        escrow.retryReputationUpdate(user, campaignId, claim.questId);
        assertFalse(escrow.pendingReputationUpdates(campaignId, claim.questId, user));
        (uint64 points,,,,,) = reputation.reputations(user);
        assertEq(points, 10);
    }

    function testAdminRecoversOnlyNativeBalanceAboveLiability() external {
        _createNativeCampaign(block.timestamp, block.timestamp + 1 days);
        vm.deal(address(escrow), BUDGET + 1 ether);
        address payable recipient = payable(makeAddr("recoveryRecipient"));

        vm.prank(admin);
        escrow.recoverExcessBalance(address(0), recipient, 1 ether);
        assertEq(recipient.balance, 1 ether);

        vm.expectRevert(BaroCampaignEscrow.ExcessBalanceExceeded.selector);
        vm.prank(admin);
        escrow.recoverExcessBalance(address(0), recipient, 1);
    }

    function testNonOwnerCannotWithdraw() external {
        uint256 campaignId = _createNativeCampaign(block.timestamp, block.timestamp + 1 days);
        vm.warp(block.timestamp + 1 days + 1);

        vm.expectRevert(BaroCampaignEscrow.NotCampaignOwner.selector);
        vm.prank(user);
        escrow.withdrawRemainingBudget(campaignId);
    }

    function testFuzzRejectsRewardAboveMaximum(uint96 excess) external {
        excess = uint96(bound(excess, 1, type(uint96).max));
        uint256 campaignId = _createNativeCampaign(block.timestamp, block.timestamp + 1 days);
        BaroCampaignEscrow.QuestClaim memory claim =
            _claim(campaignId, address(0), uint256(MAX_REWARD) + excess, 30);
        bytes memory signature = _sign(claim, OPERATOR_KEY);

        vm.expectRevert(BaroCampaignEscrow.RewardExceedsMaximum.selector);
        vm.prank(user);
        escrow.claimReward(claim, operator, signature);
    }

    function _createNativeCampaign(uint256 startTime, uint256 endTime)
        private
        returns (uint256 campaignId)
    {
        vm.deal(projectOwner, BUDGET);
        vm.prank(projectOwner);
        campaignId = escrow.createCampaign{ value: BUDGET }(
            address(0),
            BUDGET,
            MAX_REWARD,
            MAX_REWARD_PER_USER,
            startTime.toUint64(),
            endTime.toUint64()
        );
    }

    function _claim(uint256 campaignId, address token, uint256 amount, uint256 nonce)
        private
        view
        returns (BaroCampaignEscrow.QuestClaim memory)
    {
        return _claimFor(user, campaignId, token, amount, nonce);
    }

    function _claimFor(
        address recipient,
        uint256 campaignId,
        address token,
        uint256 amount,
        uint256 nonce
    ) private view returns (BaroCampaignEscrow.QuestClaim memory) {
        return _claimForQuest(recipient, campaignId, token, amount, nonce, 42);
    }

    function _claimForQuest(
        address recipient,
        uint256 campaignId,
        address token,
        uint256 amount,
        uint256 nonce,
        uint256 questId
    ) private view returns (BaroCampaignEscrow.QuestClaim memory) {
        return BaroCampaignEscrow.QuestClaim({
            user: recipient,
            campaignId: campaignId,
            questId: questId,
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
