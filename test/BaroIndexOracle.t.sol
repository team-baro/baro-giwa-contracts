// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { BaroIndexOracle } from "../src/BaroIndexOracle.sol";

contract BaroIndexOracleTest is Test {
    BaroIndexOracle internal oracle;
    uint256 internal constant DAY = 20_000;
    bytes32 internal constant PROJECT = keccak256("baro");
    bytes32 internal constant SOURCE = keccak256("aggregate");

    function setUp() public {
        vm.warp(DAY * 1 days + 12 hours);
        oracle = new BaroIndexOracle(address(this), address(this));
    }

    function testPublishesAndReadsHistory() public {
        (uint256 emptyDay, BaroIndexOracle.Snapshot memory empty) = oracle.latestSnapshot();
        assertEq(emptyDay, 0);
        assertFalse(empty.exists);
        bytes32 root = oracle.projectLeaf(DAY, PROJECT, 5_000, -250);
        oracle.publish(DAY, 55, root, SOURCE);
        (uint256 day, BaroIndexOracle.Snapshot memory snapshot) = oracle.latestSnapshot();
        assertEq(day, DAY);
        assertEq(snapshot.fearGreed, 55);
        assertEq(snapshot.sourceHash, SOURCE);
        assertEq(snapshot.publishedAt, block.timestamp);
        assertEq(oracle.snapshotCount(), 1);
        assertTrue(oracle.verifyProject(DAY, PROJECT, 5_000, -250, new bytes32[](0)));
        assertFalse(oracle.verifyProject(DAY, PROJECT, 5_001, -250, new bytes32[](0)));
        assertFalse(oracle.verifyProject(DAY - 1, PROJECT, 5_000, -250, new bytes32[](0)));
    }

    function testRejectsMissingPublisherAndUnauthorizedPublication() public {
        vm.expectRevert(BaroIndexOracle.InvalidAddress.selector);
        new BaroIndexOracle(address(this), address(0));
        vm.prank(address(123));
        vm.expectRevert();
        oracle.publish(DAY, 50, PROJECT, SOURCE);
    }

    function testRejectsPastAndFutureDays() public {
        vm.expectRevert(BaroIndexOracle.NotCurrentDay.selector);
        oracle.publish(DAY - 1, 50, PROJECT, SOURCE);
        vm.expectRevert(BaroIndexOracle.NotCurrentDay.selector);
        oracle.publish(DAY + 1, 50, PROJECT, SOURCE);
    }

    function testMidnightChangesAllowedDay() public {
        vm.warp((DAY + 1) * 1 days - 1);
        oracle.publish(DAY, 50, PROJECT, SOURCE);
        vm.warp((DAY + 1) * 1 days);
        vm.expectRevert(BaroIndexOracle.NotCurrentDay.selector);
        oracle.publish(DAY, 60, PROJECT, SOURCE);
        oracle.publish(DAY + 1, 60, PROJECT, SOURCE);
        assertEq(oracle.latestDay(), DAY + 1);
    }

    function testRejectsEmptyCommitments() public {
        vm.expectRevert(BaroIndexOracle.InvalidSnapshot.selector);
        oracle.publish(DAY, 50, bytes32(0), SOURCE);
        vm.expectRevert(BaroIndexOracle.InvalidSnapshot.selector);
        oracle.publish(DAY, 50, PROJECT, bytes32(0));
    }

    function testFuzzRejectsInvalidFearGreed(uint8 value) public {
        value = uint8(bound(value, 101, 255));
        vm.expectRevert(BaroIndexOracle.InvalidSnapshot.selector);
        oracle.publish(DAY, value, PROJECT, SOURCE);
    }

    function testFuzzRejectsInvalidProjectValues(uint16 share, int32 gap) public {
        vm.assume(share > 10_000 || gap < -10_000 || gap > 10_000);
        vm.expectRevert(BaroIndexOracle.InvalidSnapshot.selector);
        oracle.projectLeaf(DAY, PROJECT, share, gap);
    }

    function testRejectsZeroProjectId() public {
        vm.expectRevert(BaroIndexOracle.InvalidSnapshot.selector);
        oracle.projectLeaf(DAY, bytes32(0), 0, 0);
    }

    function testTwoProjectMerkleProof() public {
        bytes32 a = oracle.projectLeaf(DAY, PROJECT, 5_000, 200);
        bytes32 b = oracle.projectLeaf(DAY, keccak256("other"), 5_000, -200);
        bytes32 root = a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
        oracle.publish(DAY, 50, root, SOURCE);
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = b;
        assertTrue(oracle.verifyProject(DAY, PROJECT, 5_000, 200, proof));
        assertFalse(oracle.verifyProject(DAY, PROJECT, 5_000, -200, proof));
    }
}
