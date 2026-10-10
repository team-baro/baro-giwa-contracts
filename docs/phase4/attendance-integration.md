# Attendance integration

Deploy BaroAttendance against the chain's EAS contract and a registered, irrevocable, resolver-free schema:
`uint256 sessionId,uint8 kind,bytes32 metadataHash`.
The contract validates the schema at construction. No fees or separate NFT are supported.

An ORGANIZER_ROLE wallet creates a session before it starts. Its organizer, times, kind and metadata are immutable.
The organizer verifies attendance offchain, then signs AttendanceClaim(uint256 sessionId,address user,uint256 deadline).
Domain: name BaroAttendance, version 1, actual chainId, verifyingContract = this attendance deployment.
Set deadline <= session end. Recipients call claim(sessionId, deadline, signature) during [start,end).
For a smart contract organizer, use its ERC-1271 signature format. The recipient must submit from its own wallet.

Resolve AttendanceAttested to an EAS UID; read EAS to verify attester, schema, recipient and payload.
Only confirmed successful receipts count as issued. An EAS failure or zero UID rolls back the claim slot.
Unconfirmed requests are pending, never issued. Session end does not retroactively expire issued attendance.
Revoking organizer authority blocks its outstanding signatures. Admin pause blocks new claims.

Organizer approval proves Baro approved attendance, not that physical presence was independently measured.
The UI, attendance evidence collection and signer service are outside this contract repository.
