// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { ERC1271WalletMock } from "@openzeppelin/contracts/mocks/ERC1271WalletMock.sol";
import { BaroPerformanceEscrow } from "../src/BaroPerformanceEscrow.sol";
import { IWalletEligibility } from "../src/interfaces/IWalletEligibility.sol";
import { MockEligibility } from "./mocks/MockEligibility.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { TaxToken, PerformanceReceiver } from "./mocks/PerformanceActors.sol";

abstract contract PerformanceFixture is Test {
    BaroPerformanceEscrow internal escrow;
    uint256 internal constant KEY = 0xB0B;
    uint64 internal constant START = 1_000_100;
    uint64 internal constant END = 1_003_700;
    address internal verifier;
    address internal owner = address(0x1111);
    address internal channel = address(0x2222);
    address internal user = address(0x3333);

    function setUp() public virtual {
        vm.warp(1_000_000);
        verifier = vm.addr(KEY);
        escrow = new BaroPerformanceEscrow(address(this), verifier);
        escrow.grantRole(escrow.CREATOR_ROLE(), owner);
        vm.deal(owner, 100 ether);
    }

    function terms() internal view returns (BaroPerformanceEscrow.Terms memory) {
        return BaroPerformanceEscrow.Terms({
            channel: channel,
            token: address(0),
            verifier: verifier,
            eligibility: IWalletEligibility(address(0)),
            budget: 10 ether,
            unitReward: 1 ether,
            start: START,
            end: END,
            conditionHash: keccak256("confirmed deposit event")
        });
    }

    function create(BaroPerformanceEscrow.Terms memory t) internal returns (uint256 id) {
        vm.prank(owner);
        return escrow.createCampaign{ value: t.token == address(0) ? t.budget : 0 }(t);
    }

    function receipt(uint256 id)
        internal
        view
        returns (BaroPerformanceEscrow.ActionReceipt memory)
    {
        return BaroPerformanceEscrow.ActionReceipt({
            campaignId: id,
            user: user,
            channel: channel,
            evidenceHash: keccak256(abi.encode(id, user, "chainId txHash logIndex")),
            actionAt: START,
            deadline: END
        });
    }

    function sign(BaroPerformanceEscrow.ActionReceipt memory r)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 a, bytes32 b) = vm.sign(KEY, escrow.hashReceipt(r));
        return abi.encodePacked(a, b, v);
    }

    function rejectReceipt(BaroPerformanceEscrow.ActionReceipt memory r, bytes4 reason) internal {
        bytes memory sig = sign(r);
        vm.expectRevert(reason);
        escrow.settle(r, sig);
    }
}

contract BaroPerformanceEscrowTest is PerformanceFixture {
    function testNativePayoutAndOwnerRefund() public {
        uint256 id = create(terms());
        vm.warp(START);
        BaroPerformanceEscrow.ActionReceipt memory r = receipt(id);
        escrow.settle(r, sign(r));
        assertEq(channel.balance, 1 ether);
        assertEq(user.balance, 0);
        assertEq(escrow.totalLiability(address(0)), 9 ether);
        BaroPerformanceEscrow.Campaign memory c = escrow.getCampaign(id);
        assertEq(c.remainingBudget, 9 ether);
        assertEq(c.paidBudget, 1 ether);
        vm.warp(END);
        vm.prank(owner);
        escrow.refund(id);
        assertEq(owner.balance, 99 ether);
        assertEq(address(escrow).balance, 0);
        assertEq(escrow.totalLiability(address(0)), 0);
        vm.prank(owner);
        vm.expectRevert(BaroPerformanceEscrow.RefundUnavailable.selector);
        escrow.refund(id);
    }

    function testERC20PayoutAndRefund() public {
        MockERC20 token = new MockERC20();
        token.mint(owner, 10 ether);
        escrow.setRewardTokenSupported(address(token), true);
        vm.prank(owner);
        token.approve(address(escrow), 10 ether);
        BaroPerformanceEscrow.Terms memory t = terms();
        t.token = address(token);
        uint256 id = create(t);
        vm.warp(START);
        BaroPerformanceEscrow.ActionReceipt memory r = receipt(id);
        escrow.settle(r, sign(r));
        assertEq(token.balanceOf(channel), 1 ether);
        vm.warp(END);
        vm.prank(owner);
        escrow.refund(id);
        assertEq(token.balanceOf(owner), 9 ether);
        assertEq(escrow.totalLiability(address(token)), 0);
    }

    function testDuplicateUserAndEvidenceRejected() public {
        uint256 id = create(terms());
        uint256 second = create(terms());
        vm.warp(START);
        BaroPerformanceEscrow.ActionReceipt memory r = receipt(id);
        escrow.settle(r, sign(r));
        r.evidenceHash = keccak256("new evidence");
        rejectReceipt(r, BaroPerformanceEscrow.AlreadyRewarded.selector);
        r = receipt(id);
        r.campaignId = second;
        r.user = address(444);
        rejectReceipt(r, BaroPerformanceEscrow.AlreadyRewarded.selector);
        assertEq(channel.balance, 1 ether);
    }

    function testCannotRedirectPayoutOrChangeWalletAfterSigning() public {
        uint256 id = create(terms());
        vm.warp(START);
        BaroPerformanceEscrow.ActionReceipt memory r = receipt(id);
        r.channel = address(555);
        rejectReceipt(r, BaroPerformanceEscrow.InvalidReceipt.selector);
        r = receipt(id);
        bytes memory sig = sign(r);
        r.user = address(555);
        vm.expectRevert(BaroPerformanceEscrow.InvalidReceipt.selector);
        escrow.settle(r, sig);
    }

    function testRejectsInvalidActionTimesAndDeadlines() public {
        uint256 id = create(terms());
        vm.warp(START);
        BaroPerformanceEscrow.ActionReceipt memory r = receipt(id);
        r.actionAt = START - 1;
        rejectReceipt(r, BaroPerformanceEscrow.InvalidReceipt.selector);
        r.actionAt = END;
        rejectReceipt(r, BaroPerformanceEscrow.InvalidReceipt.selector);
        r.actionAt = START + 1;
        rejectReceipt(r, BaroPerformanceEscrow.InvalidReceipt.selector);
        r = receipt(id);
        r.deadline = START - 1;
        rejectReceipt(r, BaroPerformanceEscrow.InvalidReceipt.selector);
        r.deadline = END + 1;
        rejectReceipt(r, BaroPerformanceEscrow.InvalidReceipt.selector);
        r = receipt(id);
        r.user = address(0);
        rejectReceipt(r, BaroPerformanceEscrow.InvalidReceipt.selector);
        r = receipt(id);
        r.evidenceHash = bytes32(0);
        rejectReceipt(r, BaroPerformanceEscrow.InvalidReceipt.selector);
    }

    function testCampaignStartInclusiveEndExclusive() public {
        uint256 id = create(terms());
        BaroPerformanceEscrow.ActionReceipt memory r = receipt(id);
        rejectReceipt(r, BaroPerformanceEscrow.OutsideCampaignWindow.selector);
        vm.warp(START);
        escrow.settle(r, sign(r));
        r.user = address(666);
        r.evidenceHash = keccak256("second");
        vm.warp(END);
        rejectReceipt(r, BaroPerformanceEscrow.OutsideCampaignWindow.selector);
    }

    function testRevokedVerifierAndWrongSignatureRejected() public {
        uint256 id = create(terms());
        vm.warp(START);
        BaroPerformanceEscrow.ActionReceipt memory r = receipt(id);
        vm.expectRevert(BaroPerformanceEscrow.InvalidReceipt.selector);
        escrow.settle(r, hex"00");
        escrow.revokeRole(escrow.VERIFIER_ROLE(), verifier);
        rejectReceipt(r, BaroPerformanceEscrow.InvalidReceipt.selector);
    }

    function testERC1271CampaignVerifier() public {
        ERC1271WalletMock wallet = new ERC1271WalletMock(verifier);
        escrow.grantRole(escrow.VERIFIER_ROLE(), address(wallet));
        BaroPerformanceEscrow.Terms memory t = terms();
        t.verifier = address(wallet);
        uint256 id = create(t);
        vm.warp(START);
        BaroPerformanceEscrow.ActionReceipt memory r = receipt(id);
        escrow.settle(r, sign(r));
        assertEq(channel.balance, 1 ether);
    }

    function testSignaturesCannotCrossChainsOrDeployments() public {
        uint256 id = create(terms());
        vm.warp(START);
        BaroPerformanceEscrow.ActionReceipt memory r = receipt(id);
        bytes memory sig = sign(r);
        vm.chainId(block.chainid + 1);
        vm.expectRevert(BaroPerformanceEscrow.InvalidReceipt.selector);
        escrow.settle(r, sig);
        vm.chainId(block.chainid - 1);
        vm.warp(1_000_000);
        BaroPerformanceEscrow other = new BaroPerformanceEscrow(address(this), verifier);
        other.grantRole(other.CREATOR_ROLE(), owner);
        vm.prank(owner);
        other.createCampaign{ value: 10 ether }(terms());
        vm.warp(START);
        vm.expectRevert(BaroPerformanceEscrow.InvalidReceipt.selector);
        other.settle(r, sig);
    }

    function testEligibilityIsCheckedAtSettlement() public {
        MockEligibility eligible = new MockEligibility();
        BaroPerformanceEscrow.Terms memory t = terms();
        t.eligibility = eligible;
        uint256 id = create(t);
        vm.warp(START);
        BaroPerformanceEscrow.ActionReceipt memory r = receipt(id);
        rejectReceipt(r, BaroPerformanceEscrow.IneligibleWallet.selector);
        eligible.configure(user, true, true);
        rejectReceipt(r, BaroPerformanceEscrow.IneligibleWallet.selector);
        assertFalse(escrow.rewardedUsers(id, user));
        eligible.configure(user, true, false);
        escrow.settle(r, sign(r));
        assertEq(channel.balance, 1 ether);
    }

    function testPauseBlocksFundingAndPayoutButNotMaturedRefund() public {
        uint256 id = create(terms());
        escrow.pause();
        vm.prank(owner);
        vm.expectRevert();
        escrow.createCampaign{ value: 10 ether }(terms());
        vm.warp(START);
        BaroPerformanceEscrow.ActionReceipt memory r = receipt(id);
        bytes memory sig = sign(r);
        vm.expectRevert();
        escrow.settle(r, sig);
        escrow.unpause();
        escrow.settle(r, sig);
        escrow.pause();
        vm.warp(END);
        vm.prank(owner);
        escrow.refund(id);
        assertEq(escrow.totalLiability(address(0)), 0);
    }

    function testOnlyOwnerCanRefundAfterEnd() public {
        uint256 id = create(terms());
        vm.prank(owner);
        vm.expectRevert(BaroPerformanceEscrow.RefundUnavailable.selector);
        escrow.refund(id);
        vm.warp(END);
        vm.expectRevert(BaroPerformanceEscrow.RefundUnavailable.selector);
        escrow.refund(id);
        vm.prank(verifier);
        vm.expectRevert(BaroPerformanceEscrow.RefundUnavailable.selector);
        escrow.refund(id);
        assertEq(address(escrow).balance, 10 ether);
        (bool ok,) = address(escrow).call(abi.encodeWithSignature("withdraw(uint256)", id));
        assertFalse(ok);
    }

    function testNativePayoutFailureRollsBackReceipt() public {
        PerformanceReceiver receiver = new PerformanceReceiver();
        receiver.configure(true, address(0), "");
        BaroPerformanceEscrow.Terms memory t = terms();
        t.channel = address(receiver);
        uint256 id = create(t);
        vm.warp(START);
        BaroPerformanceEscrow.ActionReceipt memory r = receipt(id);
        r.channel = address(receiver);
        bytes memory sig = sign(r);
        vm.expectRevert();
        escrow.settle(r, sig);
        assertFalse(escrow.rewardedUsers(id, user));
        assertFalse(escrow.usedEvidence(r.evidenceHash));
        assertEq(escrow.totalLiability(address(0)), 10 ether);
        receiver.configure(false, address(0), "");
        escrow.settle(r, sig);
        assertEq(address(receiver).balance, 1 ether);
    }

    function testChannelCannotReenterSettlement() public {
        PerformanceReceiver receiver = new PerformanceReceiver();
        BaroPerformanceEscrow.Terms memory t = terms();
        t.channel = address(receiver);
        uint256 id = create(t);
        vm.warp(START);
        BaroPerformanceEscrow.ActionReceipt memory r = receipt(id);
        r.channel = address(receiver);
        bytes memory sig = sign(r);
        receiver.configure(false, address(escrow), abi.encodeCall(escrow.settle, (r, sig)));
        escrow.settle(r, sig);
        assertFalse(receiver.callbackSucceeded());
        assertEq(address(receiver).balance, 1 ether);
        assertEq(escrow.getCampaign(id).paidBudget, 1 ether);
    }

    function testFeeOnTransferFundingAndPayoutAreRejected() public {
        TaxToken token = new TaxToken();
        token.mint(owner, 20 ether);
        escrow.setRewardTokenSupported(address(token), true);
        vm.prank(owner);
        token.approve(address(escrow), 20 ether);
        BaroPerformanceEscrow.Terms memory t = terms();
        t.token = address(token);
        token.setTax(true);
        vm.prank(owner);
        vm.expectRevert(BaroPerformanceEscrow.UnsupportedTokenBehavior.selector);
        escrow.createCampaign(t);
        assertEq(escrow.campaignCount(), 0);
        assertEq(token.balanceOf(owner), 20 ether);
        token.setTax(false);
        uint256 id = create(t);
        token.setTax(true);
        vm.warp(START);
        BaroPerformanceEscrow.ActionReceipt memory r = receipt(id);
        rejectReceipt(r, BaroPerformanceEscrow.UnsupportedTokenBehavior.selector);
        assertFalse(escrow.usedEvidence(r.evidenceHash));
        assertEq(escrow.totalLiability(address(token)), 10 ether);
    }

    function testIndependentCampaignBudgetsAndExhaustion() public {
        BaroPerformanceEscrow.Terms memory t = terms();
        t.budget = 1 ether;
        uint256 id = create(t);
        uint256 second = create(terms());
        vm.warp(START);
        BaroPerformanceEscrow.ActionReceipt memory r = receipt(id);
        escrow.settle(r, sign(r));
        r.user = address(777);
        r.evidenceHash = keccak256("new");
        rejectReceipt(r, BaroPerformanceEscrow.InsufficientBudget.selector);
        assertEq(escrow.getCampaign(second).remainingBudget, 10 ether);
        assertEq(escrow.totalLiability(address(0)), 10 ether);
    }

    function testInvalidFundingAndTokenSupport() public {
        BaroPerformanceEscrow.Terms memory t = terms();
        vm.prank(owner);
        vm.expectRevert(BaroPerformanceEscrow.InvalidFunding.selector);
        escrow.createCampaign{ value: 1 }(t);
        MockERC20 token = new MockERC20();
        t.token = address(token);
        vm.prank(owner);
        vm.expectRevert(BaroPerformanceEscrow.UnsupportedToken.selector);
        escrow.createCampaign(t);
        escrow.setRewardTokenSupported(address(token), true);
        vm.prank(owner);
        vm.expectRevert(BaroPerformanceEscrow.InvalidFunding.selector);
        escrow.createCampaign{ value: 1 }(t);
        vm.expectRevert(BaroPerformanceEscrow.InvalidConfiguration.selector);
        escrow.setRewardTokenSupported(address(1), true);
    }

    function testInvalidTermsAndRoleGuards() public {
        vm.expectRevert(BaroPerformanceEscrow.InvalidConfiguration.selector);
        new BaroPerformanceEscrow(address(this), address(0));
        BaroPerformanceEscrow.Terms memory t = terms();
        vm.expectRevert();
        escrow.createCampaign(t);
        vm.prank(owner);
        vm.expectRevert();
        escrow.pause();
        vm.prank(owner);
        vm.expectRevert();
        escrow.setRewardTokenSupported(address(0), false);
        vm.expectRevert(BaroPerformanceEscrow.InvalidCampaign.selector);
        escrow.getCampaign(1);
        vm.startPrank(owner);
        t.channel = address(0);
        vm.expectRevert(BaroPerformanceEscrow.InvalidConfiguration.selector);
        escrow.createCampaign(t);
        t.channel = address(escrow);
        vm.expectRevert(BaroPerformanceEscrow.InvalidConfiguration.selector);
        escrow.createCampaign(t);
        t = terms();
        t.verifier = address(123);
        vm.expectRevert(BaroPerformanceEscrow.InvalidConfiguration.selector);
        escrow.createCampaign(t);
        t = terms();
        t.budget = 0;
        vm.expectRevert(BaroPerformanceEscrow.InvalidConfiguration.selector);
        escrow.createCampaign(t);
        t = terms();
        t.unitReward = 0;
        vm.expectRevert(BaroPerformanceEscrow.InvalidConfiguration.selector);
        escrow.createCampaign(t);
        t = terms();
        t.unitReward = 11 ether;
        vm.expectRevert(BaroPerformanceEscrow.InvalidConfiguration.selector);
        escrow.createCampaign(t);
        t = terms();
        t.start = 999_999;
        vm.expectRevert(BaroPerformanceEscrow.InvalidConfiguration.selector);
        escrow.createCampaign(t);
        t = terms();
        t.end = START;
        vm.expectRevert(BaroPerformanceEscrow.InvalidConfiguration.selector);
        escrow.createCampaign(t);
        t = terms();
        t.conditionHash = bytes32(0);
        vm.expectRevert(BaroPerformanceEscrow.InvalidConfiguration.selector);
        escrow.createCampaign(t);
        t = terms();
        t.eligibility = IWalletEligibility(address(1));
        vm.expectRevert(BaroPerformanceEscrow.InvalidConfiguration.selector);
        escrow.createCampaign(t);
        vm.stopPrank();
    }

    function testFuzzBudgetConservation(uint128 budget, uint128 reward) public {
        budget = uint128(bound(budget, 1 ether, 20 ether));
        reward = uint128(bound(reward, 1, budget));
        BaroPerformanceEscrow.Terms memory t = terms();
        t.budget = budget;
        t.unitReward = reward;
        uint256 id = create(t);
        vm.warp(START);
        BaroPerformanceEscrow.ActionReceipt memory r = receipt(id);
        escrow.settle(r, sign(r));
        BaroPerformanceEscrow.Campaign memory c = escrow.getCampaign(id);
        assertEq(c.remainingBudget + c.paidBudget, budget);
        assertEq(c.paidBudget, reward);
        assertEq(address(escrow).balance, escrow.totalLiability(address(0)));
    }
}
