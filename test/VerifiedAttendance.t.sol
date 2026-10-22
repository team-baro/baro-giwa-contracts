// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { BaroAttendanceTest } from "./BaroAttendance.t.sol";
import { BaroAttendance } from "../src/BaroAttendance.sol";
import { IWalletEligibility } from "../src/interfaces/IWalletEligibility.sol";
import { MockEligibility } from "./mocks/MockEligibility.sol";

contract VerifiedAttendanceTest is BaroAttendanceTest {
    function testOnlyEligibleWalletCanClaimVerifiedSession() public {
        MockEligibility verifier = new MockEligibility();
        attendance = new BaroAttendance(address(this), organizer, eas, schema, verifier);
        vm.prank(organizer);
        attendance.createVerifiedSession(1, START, END, 0, META);
        bytes memory sig = signature(1, user, END);
        vm.prank(user);
        vm.expectRevert(BaroAttendance.IneligibleWallet.selector);
        attendance.claim(1, END, sig);
        assertFalse(attendance.claimed(1, user));
        verifier.configure(user, true, false);
        vm.prank(user);
        attendance.claim(1, END, sig);
        assertEq(attendance.attestationCount(), 1);
        assertTrue(attendance.verifiedSessions(1));
    }

    function testVerifiedSessionRequiresConfiguredVerifier() public {
        vm.prank(organizer);
        vm.expectRevert(BaroAttendance.InvalidConfiguration.selector);
        attendance.createVerifiedSession(2, START, END, 0, META);
        vm.expectRevert(BaroAttendance.InvalidConfiguration.selector);
        new BaroAttendance(address(this), organizer, eas, schema, IWalletEligibility(address(1)));
    }
}
