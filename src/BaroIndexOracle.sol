// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title BaroIndexOracle
/// @notice Append-only daily observations; data accuracy is the publisher's responsibility.
contract BaroIndexOracle {
    struct Snapshot {
        uint8 fearGreed;
        bytes32 projectRoot;
        bytes32 sourceHash;
        uint256 publishedAt;
        bool exists;
    }
    mapping(uint256 day => Snapshot snapshot) public snapshots;
}
