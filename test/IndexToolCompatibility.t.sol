// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { BaroIndexOracle } from "../src/BaroIndexOracle.sol";

/// @dev Golden root/proof produced by tools/prepare_index.py through cast's ABI encoder.
contract IndexToolCompatibilityTest is Test {
    function testPreparedThreeProjectTreeMatchesContract() public {
        vm.warp(20000 days);
        BaroIndexOracle oracle = new BaroIndexOracle(address(this), address(this));
        bytes32 root = 0xda778be4ea8ad774407715216b55476a98feeb203b2751026375b53860c2973e;
        oracle.publish(
            20000, 50, root, 0x6e1ba890737336470df6994475300c0a06506623562a24683c7b26b69a4dbe99
        );
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0xc7fef8102c2ac83ae376779656535e2bb7f1f507bafc4351878dab83b78838b3;
        assertTrue(oracle.verifyProject(20000, bytes32(uint256(3)), 1000, -100, proof));
        assertFalse(oracle.verifyProject(20000, bytes32(uint256(3)), 1000, 100, proof));
    }
}
