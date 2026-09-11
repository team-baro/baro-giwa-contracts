// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Script } from "forge-std/Script.sol";
import { BaroIndexOracle } from "../src/BaroIndexOracle.sol";

/// @notice Idempotent same-payload publication; a conflicting existing snapshot aborts.
contract PublishIndex is Script {
    function run() external returns (bool submitted) {
        require(block.chainid == 91_342, "Wrong chain");
        BaroIndexOracle oracle = BaroIndexOracle(vm.envAddress("BARO_INDEX_ORACLE"));
        address publisher = vm.envAddress("BARO_PUBLISHER_ADDRESS");
        uint256 day = vm.envUint("BARO_INDEX_DAY");
        uint256 fear = vm.envUint("BARO_FEAR_GREED");
        bytes32 root = vm.envBytes32("BARO_PROJECT_ROOT");
        bytes32 source = vm.envBytes32("BARO_SOURCE_HASH");
        require(day == block.timestamp / 1 days, "Not current UTC day");
        require(fear <= 100 && root != bytes32(0) && source != bytes32(0), "Invalid snapshot");
        require(oracle.hasRole(oracle.PUBLISHER_ROLE(), publisher), "Missing publisher role");
        (uint8 oldFear, bytes32 oldRoot, bytes32 oldSource,, bool exists) = oracle.snapshots(day);
        if (exists) {
            require(oldFear == fear && oldRoot == root && oldSource == source, "Snapshot conflict");
            return false;
        }
        vm.startBroadcast(publisher);
        // Safe after validating the input range above.
        // forge-lint: disable-next-line(unsafe-typecast)
        oracle.publish(day, uint8(fear), root, source);
        vm.stopBroadcast();
        return true;
    }
}
