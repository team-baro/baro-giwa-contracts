// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { BaroCampaignEscrow } from "../src/BaroCampaignEscrow.sol";
import { IBaroReputationSBT } from "../src/interfaces/IBaroReputationSBT.sol";
import { DojangEligibility } from "../src/DojangEligibility.sol";
import { IDojangScroll } from "../src/interfaces/IWalletEligibility.sol";
import { MockEAS } from "./mocks/MockEAS.sol";
import { MockDojangScroll } from "./mocks/MockEligibility.sol";

contract GasBurningReputation is IBaroReputationSBT {
    bool public burn = true;
    uint256 public completions;

    function setBurn(bool value) external {
        burn = value;
    }

    function recordQuestCompletion(address, uint256, uint256, uint32) external {
        if (burn) assembly { for { } 1 { } { } }
        completions += 1;
    }
}

contract ReviewRegressionTest is Test {
    uint256 internal constant KEY = 0xB0B;
    address internal operator;
    address internal constant OWNER = address(0xCAFE);
    address internal constant USER = address(0xBEEF);
    BaroCampaignEscrow internal escrow;
    uint256 internal campaignId;
    GasBurningReputation internal reputation;

    function setUp() public {
        vm.warp(1_000_000);
        operator = vm.addr(KEY);
        reputation = new GasBurningReputation();
        escrow = new BaroCampaignEscrow(address(this), operator, reputation);
        bytes32 role = escrow.CAMPAIGN_CREATOR_ROLE();
        vm.prank(operator);
        escrow.grantRole(role, OWNER);
        vm.deal(OWNER, 10 ether);
        vm.prank(OWNER);
        campaignId = escrow.createCampaign{ value: 10 ether }(
            address(0), 10 ether, 1 ether, 2 ether, 1_000_000, 1_003_600
        );
    }

    function _signature(BaroCampaignEscrow.QuestClaim memory voucher)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(KEY, escrow.hashQuestClaim(voucher));
        return abi.encodePacked(r, s, v);
    }

    function testReputationOutageMustNotBlockValidReward() public {
        BaroCampaignEscrow.QuestClaim memory voucher = BaroCampaignEscrow.QuestClaim({
            user: USER,
            campaignId: campaignId,
            questId: 1,
            rewardToken: address(0),
            amount: 1 ether,
            nonce: 1,
            deadline: 1_003_600
        });
        bytes memory sig = _signature(voucher);
        vm.prank(USER);
        (bool success,) = address(escrow).call{ gas: 400_000 }(
            abi.encodeCall(escrow.claimReward, (voucher, operator, sig))
        );
        assertEq(USER.balance, success ? 1 ether : 0);
        assertEq(escrow.usedNonces(USER, 1), success);
        assertEq(escrow.pendingReputationUpdates(campaignId, 1, USER), success);
        assertTrue(success, "Reputation gas exhaustion must not revert the reward");
        assertEq(USER.balance, 1 ether);
        assertTrue(escrow.pendingReputationUpdates(campaignId, 1, USER));
        reputation.setBurn(false);
        escrow.retryReputationUpdate(USER, campaignId, 1);
        assertFalse(escrow.pendingReputationUpdates(campaignId, 1, USER));
        assertEq(reputation.completions(), 1);
    }

    function testMalformedScrollResponseShouldReturnFalse() public {
        MockEAS eas = new MockEAS();
        MockDojangScroll scroll = new MockDojangScroll();
        DojangEligibility verifier =
            new DojangEligibility(eas, scroll, address(1), keccak256("schema"));
        address user = address(0xBEEF);
        vm.mockCall(
            address(scroll),
            abi.encodeCall(scroll.isVerified, (user, verifier.UPBIT_KOREA_ID())),
            hex"01"
        );
        assertFalse(verifier.isEligible(user));
    }

    function testMalformedCurrentUIDResponseShouldReturnFalse() public {
        MockEAS eas = new MockEAS();
        MockDojangScroll scroll = new MockDojangScroll();
        DojangEligibility verifier =
            new DojangEligibility(eas, scroll, address(1), keccak256("schema"));
        address user = address(0xBEEF);
        scroll.set(user, verifier.UPBIT_KOREA_ID(), keccak256("credential"));
        vm.mockCall(
            address(scroll),
            abi.encodeCall(
                scroll.getVerifiedAddressAttestationUid, (user, verifier.UPBIT_KOREA_ID())
            ),
            hex"01"
        );
        assertFalse(verifier.isEligible(user));
    }

    function testMalformedEASResponseShouldReturnFalse() public {
        MockEAS eas = new MockEAS();
        MockDojangScroll scroll = new MockDojangScroll();
        DojangEligibility verifier =
            new DojangEligibility(eas, scroll, address(1), keccak256("schema"));
        address user = address(0xBEEF);
        bytes32 uid = keccak256("credential");
        scroll.set(user, verifier.UPBIT_KOREA_ID(), uid);
        vm.mockCall(address(eas), abi.encodeCall(eas.getAttestation, (uid)), hex"01");
        assertFalse(verifier.isEligible(user));
    }

    function testLowGasCannotSilentlySkipReputation() public {
        BaroCampaignEscrow.QuestClaim memory voucher = BaroCampaignEscrow.QuestClaim({
            user: USER,
            campaignId: campaignId,
            questId: 1,
            rewardToken: address(0),
            amount: 1 ether,
            nonce: 1,
            deadline: 1_003_600
        });
        bytes memory sig = _signature(voucher);
        vm.prank(USER);
        (bool success, bytes memory result) = address(escrow).call{ gas: 300_000 }(
            abi.encodeCall(escrow.claimReward, (voucher, operator, sig))
        );
        assertFalse(success);
        assertEq(bytes4(result), BaroCampaignEscrow.InsufficientReputationGas.selector);
        assertEq(USER.balance, 0);
        assertFalse(escrow.usedNonces(USER, 1));
        assertFalse(escrow.pendingReputationUpdates(campaignId, 1, USER));
        vm.prank(USER);
        (success,) = address(escrow).call{ gas: 400_000 }(
            abi.encodeCall(escrow.claimReward, (voucher, operator, sig))
        );
        assertTrue(success);
        assertEq(USER.balance, 1 ether);
    }
}
