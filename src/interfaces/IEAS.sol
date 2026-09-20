// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ABI-compatible subset of ethereum-attestation-service/eas-contracts IEAS/Common/ISchemaRegistry.
// Source: https://github.com/ethereum-attestation-service/eas-contracts (MIT).
struct Attestation {
    bytes32 uid;
    bytes32 schema;
    uint64 time;
    uint64 expirationTime;
    uint64 revocationTime;
    bytes32 refUID;
    address recipient;
    address attester;
    bool revocable;
    bytes data;
}

struct AttestationRequestData {
    address recipient;
    uint64 expirationTime;
    bool revocable;
    bytes32 refUID;
    bytes data;
    uint256 value;
}

struct AttestationRequest {
    bytes32 schema;
    AttestationRequestData data;
}

struct SchemaRecord {
    bytes32 uid;
    address resolver;
    bool revocable;
    string schema;
}

interface ISchemaRegistry {
    function getSchema(bytes32 uid) external view returns (SchemaRecord memory);
    function register(string calldata schema, address resolver, bool revocable)
        external
        returns (bytes32);
}

interface IEAS {
    function attest(AttestationRequest calldata request) external payable returns (bytes32);
    function getAttestation(bytes32 uid) external view returns (Attestation memory);
    function getSchemaRegistry() external view returns (ISchemaRegistry);
}
