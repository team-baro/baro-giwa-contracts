// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { DojangEligibility } from "../src/DojangEligibility.sol";
import { IEAS, Attestation } from "../src/interfaces/IEAS.sol";
import { IDojangScroll } from "../src/interfaces/IWalletEligibility.sol";
import { MockEAS } from "./mocks/MockEAS.sol";
import { MockDojangScroll } from "./mocks/MockEligibility.sol";

contract DojangEligibilityTest is Test {
    MockEAS internal eas;
    MockDojangScroll internal scroll;
    DojangEligibility internal verifier;
    address internal user = address(0xCAFE);
    address internal issuer = address(0xB0B);
    bytes32 internal constant SCHEMA = keccak256("verified address schema");
    bytes32 internal constant UID = keccak256("credential");
    Attestation internal credential;

    function setUp() public {
        vm.warp(1_000_000);
        eas = new MockEAS();
        scroll = new MockDojangScroll();
        verifier = new DojangEligibility(eas, scroll, issuer, SCHEMA);
        credential = Attestation({
            uid: UID,
            schema: SCHEMA,
            time: 999_000,
            expirationTime: 0,
            revocationTime: 0,
            refUID: bytes32(0),
            recipient: user,
            attester: issuer,
            revocable: true,
            data: abi.encode(true)
        });
        eas.setRecord(credential);
        scroll.set(user, verifier.UPBIT_KOREA_ID(), UID);
    }

    function testCurrentUpbitCredentialQualifies() public view {
        assertTrue(verifier.isEligible(user));
    }

    function testUnverifiedAndZeroWalletsDoNotQualify() public view {
        assertFalse(verifier.isEligible(address(123)));
        assertFalse(verifier.isEligible(address(0)));
    }

    function testWrongIssuerAndSchemaDoNotQualify() public {
        credential.attester = address(55);
        eas.setRecord(credential);
        assertFalse(verifier.isEligible(user));
        credential.attester = issuer;
        credential.schema = keccak256("other");
        eas.setRecord(credential);
        assertFalse(verifier.isEligible(user));
    }

    function testWalletMustOwnCredential() public {
        scroll.set(address(123), verifier.UPBIT_KOREA_ID(), UID);
        assertFalse(verifier.isEligible(address(123)));
    }

    function testExpiredAndRevokedCredentialsDoNotQualify() public {
        credential.expirationTime = 1_000_001;
        eas.setRecord(credential);
        assertTrue(verifier.isEligible(user));
        vm.warp(1_000_001);
        assertFalse(verifier.isEligible(user));
        credential.expirationTime = 0;
        credential.revocationTime = 1;
        eas.setRecord(credential);
        assertFalse(verifier.isEligible(user));
    }

    function testFalseMalformedAndFutureCredentialsDoNotQualify() public {
        credential.data = abi.encode(false);
        eas.setRecord(credential);
        assertFalse(verifier.isEligible(user));
        credential.data = abi.encode(uint256(2));
        eas.setRecord(credential);
        assertFalse(verifier.isEligible(user));
        credential.data = hex"01";
        eas.setRecord(credential);
        assertFalse(verifier.isEligible(user));
        credential.data = abi.encode(true);
        credential.time = 1_000_001;
        eas.setRecord(credential);
        assertFalse(verifier.isEligible(user));
        credential.time = 0;
        eas.setRecord(credential);
        assertFalse(verifier.isEligible(user));
    }

    function testFaucetCredentialCannotSubstituteUpbit() public {
        scroll.set(user, verifier.UPBIT_KOREA_ID(), bytes32(0));
        scroll.set(user, keccak256("dojang.dojangattesterids.testnetfaucet"), UID);
        assertFalse(verifier.isEligible(user));
    }

    function testUIDMustMatchCurrentRecord() public {
        credential.uid = keccak256("wrong UID");
        vm.mockCall(address(eas), abi.encodeCall(eas.getAttestation, (UID)), abi.encode(credential));
        assertFalse(verifier.isEligible(user));
    }

    function testRejectsInvalidConfiguration() public {
        vm.expectRevert(DojangEligibility.InvalidConfiguration.selector);
        new DojangEligibility(IEAS(address(0)), scroll, issuer, SCHEMA);
        vm.expectRevert(DojangEligibility.InvalidConfiguration.selector);
        new DojangEligibility(eas, IDojangScroll(address(0)), issuer, SCHEMA);
        vm.expectRevert(DojangEligibility.InvalidConfiguration.selector);
        new DojangEligibility(eas, scroll, address(0), SCHEMA);
        vm.expectRevert(DojangEligibility.InvalidConfiguration.selector);
        new DojangEligibility(eas, scroll, issuer, bytes32(0));
    }

    function testExternalReadFailuresFailClosed() public {
        scroll.configure(true, false);
        assertFalse(verifier.isEligible(user));
        scroll.configure(false, true);
        assertFalse(verifier.isEligible(user));
        scroll.configure(false, false);
        eas.configure(false, true, false);
        assertFalse(verifier.isEligible(user));
        eas.configure(false, false, false);
        assertTrue(verifier.isEligible(user));
    }

    function testVerifiedFlagWithoutCurrentUIDDoesNotQualify() public {
        vm.mockCall(
            address(scroll),
            abi.encodeCall(
                scroll.getVerifiedAddressAttestationUid, (user, verifier.UPBIT_KOREA_ID())
            ),
            abi.encode(bytes32(0))
        );
        assertFalse(verifier.isEligible(user));
    }

    function testUncheckedReadIsOnlyCallableByAdapter() public {
        vm.expectRevert(DojangEligibility.OnlySelf.selector);
        verifier.readEligibility(user);
    }

    function testNoncanonicalVerificationBoolFailsClosed() public {
        vm.mockCall(
            address(scroll),
            abi.encodeCall(scroll.isVerified, (user, verifier.UPBIT_KOREA_ID())),
            abi.encode(uint256(2))
        );
        assertFalse(verifier.isEligible(user));
    }

    function testFuzzTruncatedEASResponseFailsClosed(bytes calldata returned) public {
        vm.assume(returned.length < 32);
        vm.mockCall(address(eas), abi.encodeCall(eas.getAttestation, (UID)), returned);
        assertFalse(verifier.isEligible(user));
    }
}
