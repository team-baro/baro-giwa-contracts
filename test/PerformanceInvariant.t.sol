// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { BaroPerformanceEscrow } from "../src/BaroPerformanceEscrow.sol";
import { IWalletEligibility } from "../src/interfaces/IWalletEligibility.sol";

contract PerformanceHandler is Test {
    using SafeCast for uint256;
    BaroPerformanceEscrow public escrow;
    uint256 internal constant KEY = 0xB0B;
    uint256[] public ids;
    uint256 public funded;
    uint256 public paid;
    uint256 public refunded;
    uint256 internal sequence;
    mapping(uint256 => uint256) public refunds;

    constructor(BaroPerformanceEscrow target) {
        escrow = target;
    }
    receive() external payable { }

    function count() external view returns (uint256) {
        return ids.length;
    }

    function create(uint96 seed) external {
        uint128 budget = uint128(bound(seed, 1 ether, 10 ether));
        vm.deal(address(this), address(this).balance + budget);
        BaroPerformanceEscrow.Terms memory t = BaroPerformanceEscrow.Terms({
            channel: address(0xCAFE),
            token: address(0),
            verifier: vm.addr(KEY),
            eligibility: IWalletEligibility(address(0)),
            budget: budget,
            unitReward: 1 ether,
            start: block.timestamp.toUint64(),
            end: (block.timestamp + 1 days).toUint64(),
            conditionHash: keccak256("confirmed event")
        });
        ids.push(escrow.createCampaign{ value: budget }(t));
        funded += budget;
    }

    function settle(uint256 campaignSeed, uint256 walletSeed) external {
        if (ids.length == 0) return;
        uint256 id = ids[campaignSeed % ids.length];
        BaroPerformanceEscrow.Campaign memory c = escrow.getCampaign(id);
        address user = address(uint160(bound(walletSeed, 100, 10000)));
        if (
            block.timestamp >= c.terms.end || c.remainingBudget < c.terms.unitReward
                || escrow.rewardedUsers(id, user)
        ) return;
        BaroPerformanceEscrow.ActionReceipt memory r = BaroPerformanceEscrow.ActionReceipt({
            campaignId: id,
            user: user,
            channel: c.terms.channel,
            evidenceHash: keccak256(abi.encode(++sequence)),
            actionAt: block.timestamp.toUint64(),
            deadline: c.terms.end
        });
        (uint8 v, bytes32 a, bytes32 b) = vm.sign(KEY, escrow.hashReceipt(r));
        escrow.settle(r, abi.encodePacked(a, b, v));
        paid += c.terms.unitReward;
    }

    function advance(uint32 secondsSeed) external {
        vm.warp(block.timestamp + bound(secondsSeed, 1, 2 days));
    }

    function refund(uint256 seed) external {
        if (ids.length == 0) return;
        uint256 id = ids[seed % ids.length];
        BaroPerformanceEscrow.Campaign memory c = escrow.getCampaign(id);
        if (block.timestamp < c.terms.end || c.remainingBudget == 0) return;
        escrow.refund(id);
        refunded += c.remainingBudget;
        refunds[id] += c.remainingBudget;
    }
}

contract PerformanceInvariantTest is StdInvariant, Test {
    BaroPerformanceEscrow internal escrow;
    PerformanceHandler internal handler;

    function setUp() public {
        vm.warp(1_000_000);
        escrow = new BaroPerformanceEscrow(address(this), vm.addr(0xB0B));
        handler = new PerformanceHandler(escrow);
        escrow.grantRole(escrow.CREATOR_ROLE(), address(handler));
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = handler.create.selector;
        selectors[1] = handler.settle.selector;
        selectors[2] = handler.advance.selector;
        selectors[3] = handler.refund.selector;
        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
        targetContract(address(handler));
    }

    function invariantFundsAreConserved() public view {
        uint256 remaining;
        for (uint256 i; i < handler.count(); ++i) {
            uint256 id = handler.ids(i);
            BaroPerformanceEscrow.Campaign memory c = escrow.getCampaign(id);
            assertEq(c.remainingBudget + c.paidBudget + handler.refunds(id), c.terms.budget);
            remaining += c.remainingBudget;
        }
        assertEq(remaining, escrow.totalLiability(address(0)));
        assertEq(address(escrow).balance, remaining);
        assertEq(handler.funded(), remaining + handler.paid() + handler.refunded());
    }
}
