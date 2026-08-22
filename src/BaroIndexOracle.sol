// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

/// @title BaroIndexOracle
/// @notice Append-only daily observations; data accuracy is the publisher's responsibility.
contract BaroIndexOracle is AccessControlDefaultAdminRules {
    bytes32 public constant PUBLISHER_ROLE = keccak256("PUBLISHER_ROLE");
    error InvalidAddress();

    constructor(address admin, address publisher) AccessControlDefaultAdminRules(1 days, admin) {
        if (publisher == address(0)) revert InvalidAddress();
        _grantRole(PUBLISHER_ROLE, publisher);
    }

    struct Snapshot {
        uint8 fearGreed;
        bytes32 projectRoot;
        bytes32 sourceHash;
        uint256 publishedAt;
        bool exists;
    }
    mapping(uint256 day => Snapshot snapshot) public snapshots;
    event SnapshotPublished(
        uint256 indexed day, uint8 fearGreed, bytes32 projectRoot, bytes32 sourceHash
    );

    /// @notice Publish an aggregate observation and its verifiable public source commitment.
    function publish(uint256 day, uint8 fearGreed, bytes32 projectRoot, bytes32 sourceHash)
        external
        onlyRole(PUBLISHER_ROLE)
    {
        snapshots[day] = Snapshot(fearGreed, projectRoot, sourceHash, block.timestamp, true);
        emit SnapshotPublished(day, fearGreed, projectRoot, sourceHash);
    }
}
