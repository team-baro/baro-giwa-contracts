// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { console2 } from "forge-std/console2.sol";
import { DeployPhase4 } from "../../script/DeployPhase4.s.sol";
import { IEAS, Attestation } from "../../src/interfaces/IEAS.sol";
import { IWalletEligibility, IDojangScroll } from "../../src/interfaces/IWalletEligibility.sol";
import { BaroPerformanceEscrow } from "../../src/BaroPerformanceEscrow.sol";
import { BaroQuestTestToken } from "../../src/BaroQuestTestToken.sol";
import { BaroAttendance } from "../../src/BaroAttendance.sol";

contract AttendanceContractRecipient {
    function claim(
        BaroAttendance attendance,
        uint256 session,
        uint256 deadline,
        bytes calldata signature
    ) external returns (bytes32) {
        return attendance.claim(session, deadline, signature);
    }
}

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
        _exerciseContractRecipient(deployed, key, end, cfg.eas);
        _exerciseIndexAndPayouts(deployed, key);
    }

    function _exerciseContractRecipient(
        DeployPhase4.Deployment memory deployed,
        uint256 key,
        uint64 end,
        IEAS eas
    ) private {
        AttendanceContractRecipient wallet = new AttendanceContractRecipient();
        bytes memory sig = _sign(key, deployed.attendance.hashClaim(1, address(wallet), end));
        bytes32 uid = wallet.claim(deployed.attendance, 1, end, sig);
        assertEq(eas.getAttestation(uid).recipient, address(wallet));
        assertEq(deployed.attendance.attestationCount(), 2);
    }

    function _exerciseIndexAndPayouts(DeployPhase4.Deployment memory deployed, uint256 key)
        private
    {
        uint256 day = block.timestamp / 1 days;
        bytes32 project = keccak256("synthetic fork project");
        deployed.oracle
            .publish(
                day,
                50,
                deployed.oracle.projectLeaf(day, project, 10000, -100),
                keccak256("synthetic aggregate")
            );
        assertTrue(deployed.oracle.verifyProject(day, project, 10000, -100, new bytes32[](0)));
        address owner = vm.addr(0x12345);
        address channel = vm.addr(0x23456);
        uint256 channelBefore = channel.balance;
        BaroPerformanceEscrow escrow = deployed.performance;
        escrow.grantRole(escrow.CREATOR_ROLE(), owner);
        vm.deal(owner, 3 ether);
        BaroPerformanceEscrow.Terms memory terms = BaroPerformanceEscrow.Terms({
            channel: channel,
            token: address(0),
            verifier: vm.addr(key),
            eligibility: deployed.attendance.ELIGIBILITY(),
            budget: 3 ether,
            unitReward: 1 ether,
            start: block.timestamp.toUint64(),
            end: (block.timestamp + 1 hours).toUint64(),
            conditionHash: keccak256("synthetic condition")
        });
        // Actual positive Upbit credentials are not available; only these synthetic payout campaigns omit the optional gate.
        terms.eligibility = IWalletEligibility(address(0));
        vm.prank(owner);
        uint256 nativeId = escrow.createCampaign{ value: 3 ether }(terms);
        BaroPerformanceEscrow.ActionReceipt memory receipt = BaroPerformanceEscrow.ActionReceipt({
            campaignId: nativeId,
            user: vm.addr(0x123456),
            channel: channel,
            evidenceHash: keccak256("synthetic native action"),
            actionAt: block.timestamp.toUint64(),
            deadline: terms.end
        });
        escrow.settle(receipt, _sign(key, escrow.hashReceipt(receipt)));
        assertEq(channel.balance, channelBefore + 1 ether);
        BaroQuestTestToken token = new BaroQuestTestToken(owner, 3 ether);
        escrow.setRewardTokenSupported(address(token), true);
        vm.prank(owner);
        token.approve(address(escrow), 3 ether);
        terms.token = address(token);
        vm.prank(owner);
        uint256 tokenId = escrow.createCampaign(terms);
        receipt.campaignId = tokenId;
        receipt.evidenceHash = keccak256("synthetic token action");
        escrow.settle(receipt, _sign(key, escrow.hashReceipt(receipt)));
        assertEq(token.balanceOf(channel), 1 ether);
        vm.warp(terms.end);
        vm.startPrank(owner);
        escrow.refund(nativeId);
        escrow.refund(tokenId);
        vm.stopPrank();
        assertEq(owner.balance, 2 ether);
        assertEq(token.balanceOf(owner), 2 ether);
        assertEq(escrow.totalLiability(address(0)), 0);
        assertEq(escrow.totalLiability(address(token)), 0);
    }

    function _sign(uint256 key, bytes32 digest) private pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }
}
