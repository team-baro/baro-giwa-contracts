// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { ERC1271WalletMock } from "@openzeppelin/contracts/mocks/ERC1271WalletMock.sol";
import { BaroAttendance } from "../src/BaroAttendance.sol";
import { IWalletEligibility } from "../src/interfaces/IWalletEligibility.sol";
import { IEAS, Attestation } from "../src/interfaces/IEAS.sol";
import { MockEAS } from "./mocks/MockEAS.sol";

contract BaroAttendanceTest is Test {
    BaroAttendance internal attendance;
    MockEAS internal eas;
    bytes32 internal schema;
    uint256 internal constant KEY = 0xB0B;
    address internal organizer;
    address internal user = address(0xCAFE);
    uint64 internal constant START = 1_000_100;
    uint64 internal constant END = 1_003_700;
    bytes32 internal constant META = keccak256("talk");

    function setUp() public {
        vm.warp(1_000_000);
        organizer = vm.addr(KEY);
        eas = new MockEAS();
        schema = eas.registry()
            .register("uint256 sessionId,uint8 kind,bytes32 metadataHash", address(0), false);
        attendance = new BaroAttendance(
            address(this), organizer, eas, schema, IWalletEligibility(address(0))
        );
        vm.prank(organizer);
        attendance.createSession(1, START, END, 0, META);
        vm.warp(START);
    }

    function signature(uint256 sessionId, address recipient, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(KEY, attendance.hashClaim(sessionId, recipient, deadline));
        return abi.encodePacked(r, s, v);
    }

    function testIssuesWalletBoundAttestation() public {
        bytes memory sig = signature(1, user, END);
        vm.prank(user);
        bytes32 uid = attendance.claim(1, END, sig);
        Attestation memory record = eas.getAttestation(uid);
        assertEq(record.recipient, user);
        assertEq(record.attester, address(attendance));
        assertEq(record.schema, schema);
        assertEq(record.data, abi.encode(uint256(1), uint8(0), META));
        assertFalse(record.revocable);
        assertEq(record.expirationTime, 0);
        assertEq(attendance.attestationUIDs(1, user), uid);
        assertEq(attendance.attestationCount(), 1);
        vm.prank(user);
        vm.expectRevert(BaroAttendance.AlreadyClaimed.selector);
        attendance.claim(1, END, sig);
    }

    function testRejectsWrongWalletAndSession() public {
        bytes memory sig = signature(1, user, END);
        vm.expectRevert(BaroAttendance.InvalidClaim.selector);
        attendance.claim(1, END, sig);
        vm.prank(user);
        vm.expectRevert(BaroAttendance.OutsideSessionWindow.selector);
        attendance.claim(2, END, sig);
    }

    function testRejectsExpiredOrOverlongApprovals() public {
        bytes memory sig = signature(1, user, START - 1);
        vm.prank(user);
        vm.expectRevert(BaroAttendance.InvalidClaim.selector);
        attendance.claim(1, START - 1, sig);
        sig = signature(1, user, END + 1);
        vm.prank(user);
        vm.expectRevert(BaroAttendance.InvalidClaim.selector);
        attendance.claim(1, END + 1, sig);
    }

    function testRevokedOrganizerCannotIssueOutstandingApproval() public {
        bytes memory sig = signature(1, user, END);
        attendance.revokeRole(attendance.ORGANIZER_ROLE(), organizer);
        vm.prank(user);
        vm.expectRevert(BaroAttendance.InvalidClaim.selector);
        attendance.claim(1, END, sig);
    }

    function testRejectsCrossChainAndCrossContractSignatures() public {
        bytes memory sig = signature(1, user, END);
        vm.chainId(block.chainid + 1);
        vm.prank(user);
        vm.expectRevert(BaroAttendance.InvalidClaim.selector);
        attendance.claim(1, END, sig);
        BaroAttendance other = new BaroAttendance(
            address(this), organizer, eas, schema, IWalletEligibility(address(0))
        );
        vm.prank(organizer);
        other.createSession(1, START, END, 0, META);
        vm.prank(user);
        vm.expectRevert(BaroAttendance.InvalidClaim.selector);
        other.claim(1, END, sig);
    }

    function testRejectsInvalidSessionAndUnauthorizedCreation() public {
        vm.expectRevert();
        attendance.createSession(2, START, END, 0, META);
        vm.startPrank(organizer);
        vm.expectRevert(BaroAttendance.InvalidConfiguration.selector);
        attendance.createSession(1, START, END, 0, META);
        vm.expectRevert(BaroAttendance.InvalidConfiguration.selector);
        attendance.createSession(0, START, END, 0, META);
        vm.expectRevert(BaroAttendance.InvalidConfiguration.selector);
        attendance.createSession(2, START - 1, END, 0, META);
        vm.expectRevert(BaroAttendance.InvalidConfiguration.selector);
        attendance.createSession(2, START, START, 0, META);
        vm.expectRevert(BaroAttendance.InvalidConfiguration.selector);
        attendance.createSession(2, START, END, 2, META);
        vm.expectRevert(BaroAttendance.InvalidConfiguration.selector);
        attendance.createSession(2, START, END, 0, bytes32(0));
        vm.stopPrank();
    }

    function testRejectsIncompatibleEASSchemas() public {
        vm.expectRevert(BaroAttendance.InvalidConfiguration.selector);
        new BaroAttendance(address(this), address(0), eas, schema, IWalletEligibility(address(0)));
        vm.expectRevert(BaroAttendance.InvalidConfiguration.selector);
        new BaroAttendance(
            address(this), organizer, IEAS(address(123)), schema, IWalletEligibility(address(0))
        );
        vm.expectRevert(BaroAttendance.InvalidConfiguration.selector);
        new BaroAttendance(
            address(this), organizer, eas, bytes32(0), IWalletEligibility(address(0))
        );
        vm.expectRevert(BaroAttendance.InvalidConfiguration.selector);
        new BaroAttendance(
            address(this), organizer, eas, keccak256("unknown"), IWalletEligibility(address(0))
        );
        bytes32 bad = eas.registry()
            .register("uint256 sessionId,uint8 kind,bytes32 metadataHash", address(1), false);
        vm.expectRevert(BaroAttendance.InvalidConfiguration.selector);
        new BaroAttendance(address(this), organizer, eas, bad, IWalletEligibility(address(0)));
        bad = eas.registry()
            .register("uint256 sessionId,uint8 kind,bytes32 metadataHash", address(0), true);
        vm.expectRevert(BaroAttendance.InvalidConfiguration.selector);
        new BaroAttendance(address(this), organizer, eas, bad, IWalletEligibility(address(0)));
        bad = eas.registry().register("bytes32 other", address(0), false);
        vm.expectRevert(BaroAttendance.InvalidConfiguration.selector);
        new BaroAttendance(address(this), organizer, eas, bad, IWalletEligibility(address(0)));
    }

    function testPauseAndRoleGuards() public {
        bytes memory sig = signature(1, user, END);
        attendance.pause();
        vm.prank(user);
        vm.expectRevert();
        attendance.claim(1, END, sig);
        attendance.unpause();
        vm.prank(user);
        attendance.claim(1, END, sig);
        vm.prank(user);
        vm.expectRevert();
        attendance.pause();
    }

    function testContractOrganizerSignatures() public {
        ERC1271WalletMock wallet = new ERC1271WalletMock(organizer);
        attendance.grantRole(attendance.ORGANIZER_ROLE(), address(wallet));
        vm.prank(address(wallet));
        attendance.createSession(2, START, END, 1, META);
        bytes memory sig = signature(2, user, END);
        vm.prank(user);
        attendance.claim(2, END, sig);
        assertEq(attendance.attestationCount(), 1);
    }

    function testEASRevertRollsBackAndAllowsRetry() public {
        bytes memory sig = signature(1, user, END);
        eas.configure(true, false, false);
        vm.prank(user);
        vm.expectRevert("EAS write failure");
        attendance.claim(1, END, sig);
        assertFalse(attendance.claimed(1, user));
        assertEq(attendance.attestationCount(), 0);
        eas.configure(false, false, false);
        vm.prank(user);
        attendance.claim(1, END, sig);
        assertTrue(attendance.claimed(1, user));
    }

    function testZeroUIDRollsBack() public {
        bytes memory sig = signature(1, user, END);
        eas.configure(false, false, true);
        vm.prank(user);
        vm.expectRevert(BaroAttendance.InvalidClaim.selector);
        attendance.claim(1, END, sig);
        assertFalse(attendance.claimed(1, user));
        assertEq(attendance.attestationUIDs(1, user), bytes32(0));
    }

    function testEASCallbackCannotReenter() public {
        bytes memory sig = signature(1, user, END);
        eas.setCallback(address(attendance), abi.encodeCall(attendance.claim, (1, END, sig)));
        vm.prank(user);
        attendance.claim(1, END, sig);
        assertFalse(eas.callbackSucceeded());
        assertEq(attendance.attestationCount(), 1);
        assertEq(eas.count(), 1);
    }

    function testStartInclusiveEndExclusive() public {
        bytes memory sig = signature(1, user, END);
        vm.warp(START - 1);
        vm.prank(user);
        vm.expectRevert(BaroAttendance.OutsideSessionWindow.selector);
        attendance.claim(1, END, sig);
        vm.warp(START);
        vm.prank(user);
        attendance.claim(1, END, sig);
        address second = address(0xBEEF);
        sig = signature(1, second, END);
        vm.warp(END - 1);
        vm.prank(second);
        attendance.claim(1, END, sig);
        address third = address(0xF00D);
        sig = signature(1, third, END);
        vm.warp(END);
        vm.prank(third);
        vm.expectRevert(BaroAttendance.OutsideSessionWindow.selector);
        attendance.claim(1, END, sig);
        assertEq(attendance.attestationCount(), 2);
    }

    function testFuzzOnlySessionWindowCanIssue(uint64 timestamp) public {
        vm.warp(timestamp);
        bytes memory sig = signature(1, user, END);
        vm.prank(user);
        if (timestamp < START || timestamp >= END) {
            vm.expectRevert(BaroAttendance.OutsideSessionWindow.selector);
        }
        attendance.claim(1, END, sig);
        assertEq(attendance.claimed(1, user), timestamp >= START && timestamp < END);
    }
}
