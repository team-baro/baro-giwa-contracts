// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title BaroIndexOracle
/// @notice Append-only daily observations; data accuracy is the publisher's responsibility.
contract BaroIndexOracle is AccessControlDefaultAdminRules {
    bytes32 public constant PUBLISHER_ROLE = keccak256("PUBLISHER_ROLE");
    error InvalidAddress();
    error NotCurrentDay();
    error AlreadyPublished();
    error InvalidSnapshot();

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
    uint256 public latestDay;
    uint256 public snapshotCount;
    event SnapshotPublished(
        uint256 indexed day, uint8 fearGreed, bytes32 projectRoot, bytes32 sourceHash
    );

    /// @notice Publish an aggregate observation and its verifiable public source commitment.
    function publish(uint256 day, uint8 fearGreed, bytes32 projectRoot, bytes32 sourceHash)
        external
        onlyRole(PUBLISHER_ROLE)
    {
        if (day != block.timestamp / 1 days) revert NotCurrentDay();
        if (snapshots[day].exists) revert AlreadyPublished();
        if (fearGreed > 100 || projectRoot == bytes32(0) || sourceHash == bytes32(0)) {
            revert InvalidSnapshot();
        }
        snapshots[day] = Snapshot({
            fearGreed: fearGreed,
            projectRoot: projectRoot,
            sourceHash: sourceHash,
            publishedAt: block.timestamp,
            exists: true
        });
        latestDay = day;
        snapshotCount += 1;
        emit SnapshotPublished(day, fearGreed, projectRoot, sourceHash);
    }

    /// @notice Empty history returns a Snapshot whose exists field is false.
    function latestSnapshot() external view returns (uint256 day, Snapshot memory snapshot) {
        return (latestDay, snapshots[latestDay]);
    }

    /// @notice Double-hashed, typed leaf binding the values to a specific UTC day and project.
    function projectLeaf(uint256 day, bytes32 projectId, uint16 mindshareBps, int32 gapBps)
        public
        pure
        returns (bytes32)
    {
        if (projectId == bytes32(0) || mindshareBps > 10_000 || gapBps < -10_000 || gapBps > 10_000)
        {
            revert InvalidSnapshot();
        }
        return keccak256(bytes.concat(keccak256(abi.encode(day, projectId, mindshareBps, gapBps))));
    }

    function verifyProject(
        uint256 day,
        bytes32 projectId,
        uint16 mindshareBps,
        int32 gapBps,
        bytes32[] calldata proof
    ) external view returns (bool) {
        if (!snapshots[day].exists) return false;
        return MerkleProof.verifyCalldata(
            proof, snapshots[day].projectRoot, projectLeaf(day, projectId, mindshareBps, gapBps)
        );
    }
}
