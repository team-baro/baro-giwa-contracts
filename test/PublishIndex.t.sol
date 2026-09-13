// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { BaroIndexOracle } from "../src/BaroIndexOracle.sol";
import { PublishIndex } from "../script/PublishIndex.s.sol";

contract PublishIndexTest is Test {
    BaroIndexOracle internal oracle;
    PublishIndex internal publisher;
    bytes32 internal constant ROOT = keccak256("root");
    bytes32 internal constant SOURCE = keccak256("source");
    address internal signer = address(0x1234);

    function setUp() public {
        vm.chainId(91_342);
        vm.warp(20_000 days + 1 hours);
        oracle = new BaroIndexOracle(address(this), signer);
        publisher = new PublishIndex();
    }

    function testRetryIsNoOpForSamePayload() public {
        assertTrue(publisher.publishSnapshot(oracle, signer, 20_000, 50, ROOT, SOURCE));
        assertFalse(publisher.publishSnapshot(oracle, signer, 20_000, 50, ROOT, SOURCE));
        assertEq(oracle.snapshotCount(), 1);
    }

    function testRetryRejectsConflictingPayload() public {
        assertTrue(publisher.publishSnapshot(oracle, signer, 20_000, 50, ROOT, SOURCE));
        vm.expectRevert("Snapshot conflict");
        publisher.publishSnapshot(oracle, signer, 20_000, 51, ROOT, SOURCE);
        assertEq(oracle.snapshotCount(), 1);
    }

    function testRejectsStaleDayAndWrongChain() public {
        vm.warp(20_001 days);
        vm.expectRevert("Not current UTC day");
        publisher.publishSnapshot(oracle, signer, 20_000, 50, ROOT, SOURCE);
        vm.chainId(1);
        vm.expectRevert("Wrong chain");
        publisher.publishSnapshot(oracle, signer, 20_000, 50, ROOT, SOURCE);
    }

    function testPublicationRetriesAfterRoleRepair() public {
        oracle.revokeRole(oracle.PUBLISHER_ROLE(), signer);
        vm.expectRevert("Missing publisher role");
        publisher.publishSnapshot(oracle, signer, 20_000, 50, ROOT, SOURCE);
        assertEq(oracle.snapshotCount(), 0);
        oracle.grantRole(oracle.PUBLISHER_ROLE(), signer);
        assertTrue(publisher.publishSnapshot(oracle, signer, 20_000, 50, ROOT, SOURCE));
    }
}
