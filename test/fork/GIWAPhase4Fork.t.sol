// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { console2 } from "forge-std/console2.sol";
import { DeployPhase4 } from "../../script/DeployPhase4.s.sol";
import { IEAS, Attestation } from "../../src/interfaces/IEAS.sol";
import { IDojangScroll } from "../../src/interfaces/IWalletEligibility.sol";
import { BaroAttendance } from "../../src/BaroAttendance.sol";

/// @dev Real chain code on an isolated local fork. No transactions are sent to GIWA.
contract GIWAPhase4ForkTest is Test {
    using SafeCast for uint256;

    function testOfficialEASIssuanceAndDojangReadOnFork() public {
        vm.skip(!vm.envOr("BARO_RUN_FORK_TESTS", false));
        string memory rpc = vm.envOr("GIWA_SEPOLIA_RPC_URL", string("https://sepolia-rpc.giwa.io"));
        uint256 forkBlock = vm.envOr("BARO_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) vm.createSelectFork(rpc);
        else vm.createSelectFork(rpc, forkBlock);
        assertEq(block.chainid, 91_342);
        console2.log("GIWA fork block", block.number);
        uint256 key = 0xB0B;
        address organizer = vm.addr(key);
        address user = vm.addr(0x123456);
        DeployPhase4 script = new DeployPhase4();
        DeployPhase4.Config memory cfg = DeployPhase4.Config({
            deployer: vm.addr(0x1234),
            admin: address(this),
            organizer: organizer,
            publisher: address(this),
            verifier: organizer,
            eas: IEAS(0x4200000000000000000000000000000000000021),
            scroll: IDojangScroll(0xd5077b67dcb56caC8b270C7788FC3E6ee03F17B9),
            issuer: 0x09B170CA2A006081042992bCE7379B85a02149C6,
            verifiedSchema: 0x072d75e18b2be4f89a13a7147240477481c4b526d5795802acba59046b426e08
        });
        DeployPhase4.Deployment memory deployed = script.deployStack(cfg);
        assertFalse(deployed.eligibility.isEligible(address(0)));
        assertFalse(deployed.eligibility.isEligible(user));
        uint64 start = block.timestamp.toUint64();
        uint64 end = (block.timestamp + 1 hours).toUint64();
        vm.startPrank(organizer);
        deployed.attendance.createSession(1, start, end, 0, keccak256("synthetic fork session"));
        deployed.attendance
            .createVerifiedSession(2, start, end, 0, keccak256("synthetic verified session"));
        vm.stopPrank();
        bytes memory sig = _sign(key, deployed.attendance.hashClaim(1, user, end));
        vm.prank(user);
        bytes32 uid = deployed.attendance.claim(1, end, sig);
        Attestation memory record = cfg.eas.getAttestation(uid);
        assertEq(record.uid, uid);
        assertEq(record.recipient, user);
        assertEq(record.attester, address(deployed.attendance));
        assertEq(record.schema, deployed.attendanceSchema);
        assertEq(record.data, abi.encode(uint256(1), uint8(0), keccak256("synthetic fork session")));
        assertEq(record.expirationTime, 0);
        assertFalse(record.revocable);
        assertEq(deployed.attendance.attestationCount(), 1);
        sig = _sign(key, deployed.attendance.hashClaim(2, user, end));
        vm.prank(user);
        vm.expectRevert(BaroAttendance.IneligibleWallet.selector);
        deployed.attendance.claim(2, end, sig);
        assertFalse(deployed.attendance.claimed(2, user));
    }

    function _sign(uint256 key, bytes32 digest) private pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }
}
