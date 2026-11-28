// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { DeployPhase4 } from "../script/DeployPhase4.s.sol";
import { BaroAttendance } from "../src/BaroAttendance.sol";
import { BaroPerformanceEscrow } from "../src/BaroPerformanceEscrow.sol";
import { Attestation } from "../src/interfaces/IEAS.sol";
import { IDojangScroll } from "../src/interfaces/IWalletEligibility.sol";
import { MockEAS } from "./mocks/MockEAS.sol";
import { MockDojangScroll } from "./mocks/MockEligibility.sol";

contract Phase4IntegrationTest is Test {
    DeployPhase4 internal script;
    DeployPhase4.Config internal cfg;
    DeployPhase4.Deployment internal deployed;
    MockEAS internal eas;
    MockDojangScroll internal scroll;
    uint256 internal constant KEY = 0xB0B;
    address internal organizer;
    address internal user = address(0xCAFE);
    address internal owner = address(0x1111);
    address internal channel = address(0x2222);
    bytes32 internal constant CREDENTIAL = keccak256("mock verified credential");
    uint64 internal constant START = 1_000_100;
    uint64 internal constant END = 1_003_700;

    function setUp() public {
        vm.chainId(91_342);
        vm.warp(1_000_000);
        organizer = vm.addr(KEY);
        eas = new MockEAS();
        scroll = new MockDojangScroll();
        script = new DeployPhase4();
        bytes32 verified = eas.registry().register("bool isVerified", address(0), true);
        cfg = DeployPhase4.Config({
            deployer: vm.addr(0x1234),
            admin: address(this),
            organizer: organizer,
            publisher: address(this),
            verifier: organizer,
            eas: eas,
            scroll: scroll,
            issuer: address(this),
            verifiedSchema: verified
        });
        deployed = script.deployStack(cfg);
        eas.setRecord(
            Attestation({
                uid: CREDENTIAL,
                schema: verified,
                time: 999_000,
                expirationTime: 0,
                revocationTime: 0,
                refUID: bytes32(0),
                recipient: user,
                attester: address(this),
                revocable: true,
                data: abi.encode(true)
            })
        );
        scroll.set(user, deployed.eligibility.UPBIT_KOREA_ID(), CREDENTIAL);
    }

    function signed(bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function testVerifiedAttendanceIndexAndPerformanceFlow() public {
        assertTrue(deployed.eligibility.isEligible(user));
        vm.prank(organizer);
        deployed.attendance.createVerifiedSession(1, START, END, 0, keccak256("talk"));
        deployed.performance.grantRole(deployed.performance.CREATOR_ROLE(), owner);
        vm.deal(owner, 10 ether);
        BaroPerformanceEscrow.Terms memory terms = BaroPerformanceEscrow.Terms({
            channel: channel,
            token: address(0),
            verifier: organizer,
            eligibility: deployed.eligibility,
            budget: 10 ether,
            unitReward: 1 ether,
            start: START,
            end: END,
            conditionHash: keccak256("confirmed action")
        });
        vm.prank(owner);
        uint256 id = deployed.performance.createCampaign{ value: 10 ether }(terms);
        vm.warp(START);
        bytes memory sig = signed(deployed.attendance.hashClaim(1, user, END));
        vm.prank(user);
        bytes32 uid = deployed.attendance.claim(1, END, sig);
        assertEq(eas.getAttestation(uid).recipient, user);
        uint256 day = block.timestamp / 1 days;
        bytes32 root = deployed.oracle.projectLeaf(day, keccak256("project"), 10_000, -200);
        deployed.oracle.publish(day, 55, root, keccak256("public aggregate"));
        assertTrue(
            deployed.oracle.verifyProject(day, keccak256("project"), 10_000, -200, new bytes32[](0))
        );
        BaroPerformanceEscrow.ActionReceipt memory r = BaroPerformanceEscrow.ActionReceipt({
            campaignId: id,
            user: user,
            channel: channel,
            evidenceHash: keccak256("confirmed chainId txHash logIndex"),
            actionAt: START,
            deadline: END
        });
        deployed.performance.settle(r, signed(deployed.performance.hashReceipt(r)));
        assertEq(channel.balance, 1 ether);
        assertEq(deployed.attendance.attestationCount(), 1);
        vm.warp(END);
        vm.prank(owner);
        deployed.performance.refund(id);
        assertEq(deployed.performance.totalLiability(address(0)), 0);
    }

    function testRevocationBlocksFutureVerifiedParticipation() public {
        vm.prank(organizer);
        deployed.attendance.createVerifiedSession(1, START, END, 0, keccak256("talk"));
        Attestation memory record = eas.getAttestation(CREDENTIAL);
        record.revocationTime = 1_000_000;
        eas.setRecord(record);
        vm.warp(START);
        bytes memory sig = signed(deployed.attendance.hashClaim(1, user, END));
        vm.prank(user);
        vm.expectRevert(BaroAttendance.IneligibleWallet.selector);
        deployed.attendance.claim(1, END, sig);
        assertFalse(deployed.attendance.claimed(1, user));
    }

    function testDeploymentReusesSchemaAndRejectsWrongDependencies() public {
        bytes32 schema = deployed.attendanceSchema;
        DeployPhase4.Deployment memory other = script.deployStack(cfg);
        assertEq(other.attendanceSchema, schema);
        vm.chainId(1);
        vm.expectRevert("Wrong chain");
        script.deployStack(cfg);
        vm.chainId(91_342);
        cfg.admin = address(0);
        vm.expectRevert("Missing actor");
        script.deployStack(cfg);
        cfg.admin = address(this);
        cfg.scroll = IDojangScroll(address(1));
        vm.expectRevert("Missing dependency code");
        script.deployStack(cfg);
        cfg.scroll = scroll;
        cfg.verifiedSchema = keccak256("unknown");
        vm.expectRevert("Wrong Dojang schema");
        script.deployStack(cfg);
    }
}
