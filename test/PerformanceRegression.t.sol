// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { PerformanceFixture } from "./BaroPerformanceEscrow.t.sol";
import { BaroPerformanceEscrow } from "../src/BaroPerformanceEscrow.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { PerformanceReceiver } from "./mocks/PerformanceActors.sol";

contract PerformanceRegressionTest is PerformanceFixture {
    function testRemovingTokenSupportCannotTrapFundedCampaign() public {
        MockERC20 token = new MockERC20();
        token.mint(owner, 20 ether);
        escrow.setRewardTokenSupported(address(token), true);
        vm.prank(owner);
        token.approve(address(escrow), 20 ether);
        BaroPerformanceEscrow.Terms memory t = terms();
        t.token = address(token);
        uint256 id = create(t);
        escrow.setRewardTokenSupported(address(token), false);
        vm.prank(owner);
        vm.expectRevert(BaroPerformanceEscrow.UnsupportedToken.selector);
        escrow.createCampaign(t);
        vm.warp(START);
        BaroPerformanceEscrow.ActionReceipt memory r = receipt(id);
        escrow.settle(r, sign(r));
        assertEq(token.balanceOf(channel), 1 ether);
        vm.warp(END);
        vm.prank(owner);
        escrow.refund(id);
        assertEq(token.balanceOf(owner), 19 ether);
        assertEq(escrow.totalLiability(address(token)), 0);
    }

    function testReceiptSignatureCannotBeMovedToAnotherCampaign() public {
        uint256 first = create(terms());
        uint256 second = create(terms());
        vm.warp(START);
        BaroPerformanceEscrow.ActionReceipt memory r = receipt(first);
        bytes memory sig = sign(r);
        r.campaignId = second;
        vm.expectRevert(BaroPerformanceEscrow.InvalidReceipt.selector);
        escrow.settle(r, sig);
        assertFalse(escrow.rewardedUsers(second, user));
        assertEq(escrow.totalLiability(address(0)), 20 ether);
        r.campaignId = first;
        escrow.settle(r, sig);
        assertEq(channel.balance, 1 ether);
    }

    function testNativeRefundFailurePreservesBudgetAndCanRetryWhilePaused() public {
        PerformanceReceiver receiver = new PerformanceReceiver();
        owner = address(receiver);
        escrow.grantRole(escrow.CREATOR_ROLE(), owner);
        vm.deal(owner, 10 ether);
        uint256 id = create(terms());
        receiver.configure(true, address(0), "");
        escrow.pause();
        vm.warp(END);
        vm.prank(owner);
        vm.expectRevert();
        escrow.refund(id);
        assertEq(escrow.getCampaign(id).remainingBudget, 10 ether);
        assertEq(escrow.totalLiability(address(0)), 10 ether);
        receiver.configure(false, address(escrow), abi.encodeCall(escrow.refund, (id)));
        vm.prank(owner);
        escrow.refund(id);
        assertFalse(receiver.callbackSucceeded());
        assertEq(owner.balance, 10 ether);
        assertEq(escrow.totalLiability(address(0)), 0);
    }
}
