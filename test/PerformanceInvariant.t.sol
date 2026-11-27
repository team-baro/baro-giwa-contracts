// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { BaroPerformanceEscrow } from "../src/BaroPerformanceEscrow.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
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
    MockERC20 public tokenA = new MockERC20();
    MockERC20 public tokenB = new MockERC20();
    mapping(address => uint256) public paidByToken;
    mapping(uint256 => uint256) public refunds;

    constructor(BaroPerformanceEscrow target) {
        escrow = target;
    }
    receive() external payable { }

    function count() external view returns (uint256) {
        return ids.length;
    }

    function create(uint96 seed, uint8 assetSeed) external {
        uint128 budget = uint128(bound(seed, 1 ether, 10 ether));
        address token = assetSeed % 3 == 0
            ? address(0)
            : assetSeed % 3 == 1 ? address(tokenA) : address(tokenB);
        if (token == address(0)) {
            vm.deal(address(this), address(this).balance + budget);
        } else {
            MockERC20(token).mint(address(this), budget);
            MockERC20(token).approve(address(escrow), budget);
        }
        BaroPerformanceEscrow.Terms memory t = BaroPerformanceEscrow.Terms({
            channel: address(0xCAFE),
            token: token,
            verifier: vm.addr(KEY),
            eligibility: IWalletEligibility(address(0)),
            budget: budget,
            unitReward: 1 ether,
            start: block.timestamp.toUint64(),
            end: (block.timestamp + 1 days).toUint64(),
            conditionHash: keccak256("confirmed event")
        });
        ids.push(escrow.createCampaign{ value: token == address(0) ? budget : 0 }(t));
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
        paidByToken[c.terms.token] += c.terms.unitReward;
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
        escrow.setRewardTokenSupported(address(handler.tokenA()), true);
        escrow.setRewardTokenSupported(address(handler.tokenB()), true);
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
        uint256[3] memory remainingByToken;
        for (uint256 i; i < handler.count(); ++i) {
            uint256 id = handler.ids(i);
            BaroPerformanceEscrow.Campaign memory c = escrow.getCampaign(id);
            assertEq(c.remainingBudget + c.paidBudget + handler.refunds(id), c.terms.budget);
            remaining += c.remainingBudget;
            uint256 index = c.terms.token == address(0)
                ? 0
                : c.terms.token == address(handler.tokenA()) ? 1 : 2;
            remainingByToken[index] += c.remainingBudget;
        }
        assertEq(remainingByToken[0], escrow.totalLiability(address(0)));
        assertEq(address(escrow).balance, remainingByToken[0]);
        assertEq(remainingByToken[1], escrow.totalLiability(address(handler.tokenA())));
        assertEq(remainingByToken[2], escrow.totalLiability(address(handler.tokenB())));
        assertEq(handler.tokenA().balanceOf(address(escrow)), remainingByToken[1]);
        assertEq(handler.tokenB().balanceOf(address(escrow)), remainingByToken[2]);
        assertEq(address(0xCAFE).balance, handler.paidByToken(address(0)));
        assertEq(
            handler.tokenA().balanceOf(address(0xCAFE)),
            handler.paidByToken(address(handler.tokenA()))
        );
        assertEq(
            handler.tokenB().balanceOf(address(0xCAFE)),
            handler.paidByToken(address(handler.tokenB()))
        );
        assertEq(handler.funded(), remaining + handler.paid() + handler.refunded());
    }
}
