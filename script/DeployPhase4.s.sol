// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Script } from "forge-std/Script.sol";
import { BaroIndexOracle } from "../src/BaroIndexOracle.sol";
import { BaroAttendance } from "../src/BaroAttendance.sol";
import { DojangEligibility } from "../src/DojangEligibility.sol";
import { BaroPerformanceEscrow } from "../src/BaroPerformanceEscrow.sol";
import { IEAS, ISchemaRegistry, SchemaRecord } from "../src/interfaces/IEAS.sol";
import { IDojangScroll } from "../src/interfaces/IWalletEligibility.sol";

/// @notice Simulation by default. Broadcasting requires an explicitly supplied signer and CLI flag.
contract DeployPhase4 is Script {
    string internal constant ATTENDANCE_SCHEMA =
        "uint256 sessionId,uint8 kind,bytes32 metadataHash";

    struct Config {
        address deployer;
        address admin;
        address organizer;
        address publisher;
        address verifier;
        IEAS eas;
        IDojangScroll scroll;
        address issuer;
        bytes32 verifiedSchema;
    }

    struct Deployment {
        BaroIndexOracle oracle;
        DojangEligibility eligibility;
        BaroAttendance attendance;
        BaroPerformanceEscrow performance;
        bytes32 attendanceSchema;
    }

    function run() external returns (Deployment memory) {
        Config memory cfg = Config({
            deployer: vm.envAddress("BARO_DEPLOYER_ADDRESS"),
            admin: vm.envAddress("BARO_ADMIN_ADDRESS"),
            organizer: vm.envAddress("BARO_ORGANIZER_ADDRESS"),
            publisher: vm.envAddress("BARO_PUBLISHER_ADDRESS"),
            verifier: vm.envAddress("BARO_VERIFIER_ADDRESS"),
            eas: IEAS(
                vm.envOr("BARO_EAS_ADDRESS", address(0x4200000000000000000000000000000000000021))
            ),
            scroll: IDojangScroll(
                vm.envOr("BARO_DOJANG_SCROLL", address(0xd5077b67dcb56caC8b270C7788FC3E6ee03F17B9))
            ),
            issuer: vm.envOr(
                "BARO_DOJANG_ISSUER", address(0x09B170CA2A006081042992bCE7379B85a02149C6)
            ),
            verifiedSchema: vm.envOr(
                "BARO_VERIFIED_ADDRESS_SCHEMA",
                bytes32(0x072d75e18b2be4f89a13a7147240477481c4b526d5795802acba59046b426e08)
            )
        });
        return deployStack(cfg);
    }

    function deployStack(Config memory cfg) public returns (Deployment memory deployed) {
        require(block.chainid == 91_342, "Wrong chain");
        require(
            cfg.deployer != address(0) && cfg.admin != address(0) && cfg.organizer != address(0)
                && cfg.publisher != address(0) && cfg.verifier != address(0),
            "Missing actor"
        );
        require(
            address(cfg.eas).code.length > 0 && address(cfg.scroll).code.length > 0
                && cfg.issuer.code.length > 0,
            "Missing dependency code"
        );
        ISchemaRegistry registry = cfg.eas.getSchemaRegistry();
        SchemaRecord memory verified = registry.getSchema(cfg.verifiedSchema);
        require(
            verified.uid == cfg.verifiedSchema && cfg.verifiedSchema != bytes32(0)
                && keccak256(bytes(verified.schema)) == keccak256("bool isVerified"),
            "Wrong Dojang schema"
        );
        deployed.attendanceSchema = keccak256(
            abi.encodePacked(ATTENDANCE_SCHEMA, address(0), false)
        );
        vm.startBroadcast(cfg.deployer);
        if (registry.getSchema(deployed.attendanceSchema).uid == bytes32(0)) {
            require(
                registry.register(ATTENDANCE_SCHEMA, address(0), false)
                    == deployed.attendanceSchema,
                "Wrong attendance schema"
            );
        }
        deployed.oracle = new BaroIndexOracle(cfg.admin, cfg.publisher);
        deployed.eligibility =
            new DojangEligibility(cfg.eas, cfg.scroll, cfg.issuer, cfg.verifiedSchema);
        deployed.attendance = new BaroAttendance(
            cfg.admin, cfg.organizer, cfg.eas, deployed.attendanceSchema, deployed.eligibility
        );
        deployed.performance = new BaroPerformanceEscrow(cfg.admin, cfg.verifier);
        vm.stopBroadcast();
        require(
            deployed.oracle.defaultAdmin() == cfg.admin
                && deployed.attendance.defaultAdmin() == cfg.admin
                && deployed.performance.defaultAdmin() == cfg.admin,
            "Wrong admin"
        );
    }
}
