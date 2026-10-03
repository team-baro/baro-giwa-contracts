// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {
    IEAS,
    ISchemaRegistry,
    SchemaRecord,
    Attestation,
    AttestationRequest
} from "../../src/interfaces/IEAS.sol";

/// @dev Test-only EAS ABI fixture. This is never used as deployment evidence.
contract MockSchemaRegistry is ISchemaRegistry {
    mapping(bytes32 => SchemaRecord) internal records;

    function register(string calldata text, address resolver, bool revocable)
        external
        returns (bytes32 uid)
    {
        uid = keccak256(abi.encodePacked(text, resolver, revocable));
        records[uid] =
            SchemaRecord({ uid: uid, resolver: resolver, revocable: revocable, schema: text });
    }

    function getSchema(bytes32 uid) external view returns (SchemaRecord memory) {
        return records[uid];
    }
}

contract MockEAS is IEAS {
    MockSchemaRegistry public registry = new MockSchemaRegistry();
    mapping(bytes32 => Attestation) internal records;
    uint256 public count;
    bool public failWrites;
    bool public failReads;
    bool public zeroUid;
    address public callbackTarget;
    bytes public callbackData;
    bool public callbackSucceeded;

    function configure(bool writes, bool reads, bool zero) external {
        failWrites = writes;
        failReads = reads;
        zeroUid = zero;
    }

    function setCallback(address target, bytes calldata data) external {
        callbackTarget = target;
        callbackData = data;
    }

    function getSchemaRegistry() external view returns (ISchemaRegistry) {
        return registry;
    }

    function setRecord(Attestation calldata record) external {
        records[record.uid] = record;
    }

    function getAttestation(bytes32 uid) external view returns (Attestation memory) {
        require(!failReads, "EAS read failure");
        return records[uid];
    }

    function attest(AttestationRequest calldata request) external payable returns (bytes32 uid) {
        require(!failWrites, "EAS write failure");
        if (zeroUid) return bytes32(0);
        uid = keccak256(abi.encode(msg.sender, request.data.recipient, ++count));
        records[uid] = Attestation({
            uid: uid,
            schema: request.schema,
            time: uint64(block.timestamp),
            expirationTime: request.data.expirationTime,
            revocationTime: 0,
            refUID: request.data.refUID,
            recipient: request.data.recipient,
            attester: msg.sender,
            revocable: request.data.revocable,
            data: request.data.data
        });
        if (callbackTarget != address(0)) (callbackSucceeded,) = callbackTarget.call(callbackData);
    }
}
