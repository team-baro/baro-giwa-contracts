// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

import {
    IEAS,
    SchemaRecord,
    AttestationRequest,
    AttestationRequestData
} from "./interfaces/IEAS.sol";

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import { IWalletEligibility } from "./interfaces/IWalletEligibility.sol";

/// @title BaroAttendance
/// @notice Wallet-bound EAS attendance approved by each session's authorized organizer.
contract BaroAttendance is AccessControlDefaultAdminRules, EIP712, ReentrancyGuard, Pausable {
    bytes32 public constant CLAIM_TYPEHASH =
        keccak256("AttendanceClaim(uint256 sessionId,address user,uint256 deadline)");
    error InvalidClaim();
    error IneligibleWallet();
    IWalletEligibility public immutable ELIGIBILITY;
    mapping(uint256 sessionId => bool) public verifiedSessions;
    event VerifiedSessionConfigured(uint256 indexed sessionId, address indexed verifier);
    error OutsideSessionWindow();
    error AlreadyClaimed();
    mapping(uint256 sessionId => mapping(address user => bool)) public claimed;
    mapping(uint256 sessionId => mapping(address user => bytes32 uid)) public attestationUIDs;
    uint256 public attestationCount;
    event AttendanceAttested(uint256 indexed sessionId, address indexed user, bytes32 indexed uid);
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

    constructor(
        address admin,
        address organizer,
        IEAS eas_,
        bytes32 schema_,
        IWalletEligibility eligibility_
    ) AccessControlDefaultAdminRules(1 days, admin) EIP712("BaroAttendance", "1") {
        if (organizer == address(0)) revert InvalidConfiguration();
        if (address(eas_).code.length == 0 || schema_ == bytes32(0)) revert InvalidConfiguration();
        SchemaRecord memory record = eas_.getSchemaRegistry().getSchema(schema_);
        if (
            record.uid != schema_ || record.resolver != address(0) || record.revocable
                || keccak256(bytes(record.schema)) != keccak256(bytes(SCHEMA))
        ) revert InvalidConfiguration();
        if (address(eligibility_) != address(0) && address(eligibility_).code.length == 0) {
            revert InvalidConfiguration();
        }
        ELIGIBILITY = eligibility_;
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
        if (claimed[sessionId][msg.sender]) revert AlreadyClaimed();
        if (
            session.organizer == address(0) || block.timestamp < session.start
                || block.timestamp >= session.end
        ) revert OutsideSessionWindow();
        if (
            !hasRole(ORGANIZER_ROLE, session.organizer) || deadline < block.timestamp
                || deadline > session.end
                || !SignatureChecker.isValidSignatureNow(
                    session.organizer, hashClaim(sessionId, msg.sender, deadline), signature
                )
        ) revert InvalidClaim();
    }

    /// @notice Recipient claims an irrevocable, zero-fee EAS attestation during the session.
    /// @dev Claim/count effects precede EAS; the returned UID must be stored afterward.
    ///      nonReentrant protects this final UID write; external-call failure rolls back all effects.
    // slither-disable-next-line reentrancy-benign
    function claim(uint256 sessionId, uint256 deadline, bytes calldata signature)
        external
        nonReentrant
        whenNotPaused
        returns (bytes32 uid)
    {
        _validateClaim(sessionId, deadline, signature);
        if (verifiedSessions[sessionId]) {
            try ELIGIBILITY.isEligible(msg.sender) returns (bool eligible) {
                if (!eligible) revert IneligibleWallet();
            } catch {
                revert IneligibleWallet();
            }
        }
        Session storage session = sessions[sessionId];
        claimed[sessionId][msg.sender] = true;
        attestationCount += 1;
        uid = eas.attest(
            AttestationRequest({
                schema: schema,
                data: AttestationRequestData({
                    recipient: msg.sender,
                    expirationTime: 0,
                    revocable: false,
                    refUID: bytes32(0),
                    data: abi.encode(sessionId, session.kind, session.metadataHash),
                    value: 0
                })
            })
        );
        if (uid == bytes32(0)) revert InvalidClaim();
        attestationUIDs[sessionId][msg.sender] = uid;
        emit AttendanceAttested(sessionId, msg.sender, uid);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Create a session whose claims require current Dojang eligibility.
    function createVerifiedSession(
        uint256 sessionId,
        uint64 start,
        uint64 end,
        uint8 kind,
        bytes32 metadataHash
    ) external onlyRole(ORGANIZER_ROLE) {
        if (address(ELIGIBILITY) == address(0)) revert InvalidConfiguration();
        _createSession(sessionId, start, end, kind, metadataHash);
        verifiedSessions[sessionId] = true;
        emit VerifiedSessionConfigured(sessionId, address(ELIGIBILITY));
    }
}
