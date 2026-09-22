// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

import {
    IEAS,
    ISchemaRegistry,
    SchemaRecord,
    AttestationRequest,
    AttestationRequestData
} from "./interfaces/IEAS.sol";

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @title BaroAttendance
/// @notice Wallet-bound EAS attendance approved by each session's authorized organizer.
contract BaroAttendance is AccessControlDefaultAdminRules, EIP712 {
    bytes32 public constant CLAIM_TYPEHASH =
        keccak256("AttendanceClaim(uint256 sessionId,address user,uint256 deadline)");
    error InvalidClaim();
    bytes32 public constant ORGANIZER_ROLE = keccak256("ORGANIZER_ROLE");

    struct Session {
        address organizer;
        uint64 start;
        uint64 end;
        uint8 kind;
        bytes32 metadataHash;
    }
    error InvalidConfiguration();
    mapping(uint256 sessionId => Session session) public sessions;

    IEAS public immutable eas;
    bytes32 public immutable schema;
    string public constant SCHEMA = "uint256 sessionId,uint8 kind,bytes32 metadataHash";

    constructor(address admin, address organizer, IEAS eas_, bytes32 schema_)
        AccessControlDefaultAdminRules(1 days, admin)
        EIP712("BaroAttendance", "1")
    {
        if (organizer == address(0)) revert InvalidConfiguration();
        if (address(eas_).code.length == 0 || schema_ == bytes32(0)) revert InvalidConfiguration();
        SchemaRecord memory record = eas_.getSchemaRegistry().getSchema(schema_);
        if (
            record.uid != schema_ || record.resolver != address(0) || record.revocable
                || keccak256(bytes(record.schema)) != keccak256(bytes(SCHEMA))
        ) revert InvalidConfiguration();
        eas = eas_;
        schema = schema_;
        _grantRole(ORGANIZER_ROLE, organizer);
    }

    event SessionCreated(
        uint256 indexed sessionId,
        address indexed organizer,
        uint64 start,
        uint64 end,
        uint8 kind,
        bytes32 metadataHash
    );

    /// @notice Create immutable talk (0) or quest (1) terms before the session starts.
    function createSession(
        uint256 sessionId,
        uint64 start,
        uint64 end,
        uint8 kind,
        bytes32 metadataHash
    ) external onlyRole(ORGANIZER_ROLE) {
        _createSession(sessionId, start, end, kind, metadataHash);
    }

    function _createSession(
        uint256 sessionId,
        uint64 start,
        uint64 end,
        uint8 kind,
        bytes32 metadataHash
    ) internal {
        if (
            sessionId == 0 || sessions[sessionId].organizer != address(0) || start < block.timestamp
                || end <= start || kind > 1 || metadataHash == bytes32(0)
        ) revert InvalidConfiguration();
        sessions[sessionId] = Session({
            organizer: msg.sender, start: start, end: end, kind: kind, metadataHash: metadataHash
        });
        emit SessionCreated(sessionId, msg.sender, start, end, kind, metadataHash);
    }

    function hashClaim(uint256 sessionId, address user, uint256 deadline)
        public
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(keccak256(abi.encode(CLAIM_TYPEHASH, sessionId, user, deadline)));
    }

    function _validateClaim(uint256 sessionId, uint256 deadline, bytes calldata signature)
        internal
        view
    {
        Session storage session = sessions[sessionId];
        if (
            !hasRole(ORGANIZER_ROLE, session.organizer) || deadline < block.timestamp
                || deadline > session.end
                || !SignatureChecker.isValidSignatureNow(
                    session.organizer, hashClaim(sessionId, msg.sender, deadline), signature
                )
        ) revert InvalidClaim();
    }
}
