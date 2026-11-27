// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { DeployPhase4 } from "../script/DeployPhase4.s.sol";
import { ConfigurePhase4 } from "../script/ConfigurePhase4.s.sol";
import { PublishIndex } from "../script/PublishIndex.s.sol";
import { MockEAS } from "./mocks/MockEAS.sol";
import { MockDojangScroll } from "./mocks/MockEligibility.sol";

contract Phase4ScriptEntryPointsTest is Test {
    /// @dev One sequential environment workflow avoids process-global env races between tests.
    function testDeploymentConfigurationAndPublicationEntryPoints() public {
        vm.chainId(91342);
        vm.warp(20000 days + 1 hours);
        MockEAS eas = new MockEAS();
        MockDojangScroll scroll = new MockDojangScroll();
        bytes32 verifiedSchema = eas.registry().register("bool isVerified", address(0), true);
        address deployer = vm.addr(0x1234);
        address admin = vm.addr(0xA11CE);
        address creator = vm.addr(0xC0FFEE);
        vm.deal(deployer, 100 ether);
        vm.setEnv("BARO_DEPLOYER_ADDRESS", vm.toString(deployer));
        vm.setEnv("BARO_ADMIN_ADDRESS", vm.toString(admin));
        vm.setEnv("BARO_ORGANIZER_ADDRESS", vm.toString(vm.addr(0xB0B)));
        vm.setEnv("BARO_PUBLISHER_ADDRESS", vm.toString(vm.addr(0xCAFE)));
        vm.setEnv("BARO_VERIFIER_ADDRESS", vm.toString(vm.addr(0xB0B)));
        vm.setEnv("BARO_EAS_ADDRESS", vm.toString(address(eas)));
        vm.setEnv("BARO_DOJANG_SCROLL", vm.toString(address(scroll)));
        vm.setEnv("BARO_DOJANG_ISSUER", vm.toString(address(this)));
        vm.setEnv("BARO_VERIFIED_ADDRESS_SCHEMA", vm.toString(verifiedSchema));
        DeployPhase4 deployment = new DeployPhase4();
        DeployPhase4.Deployment memory stack = deployment.run();
        assertEq(stack.oracle.defaultAdmin(), admin);
        assertEq(stack.attendance.defaultAdmin(), admin);
        assertEq(address(stack.attendance.ELIGIBILITY()), address(stack.eligibility));
        vm.setEnv("BARO_PERFORMANCE_ESCROW", vm.toString(address(stack.performance)));
        vm.setEnv("BARO_CAMPAIGN_CREATOR", vm.toString(creator));
        vm.setEnv("BARO_REWARD_TOKEN", vm.toString(address(0)));
        ConfigurePhase4 configuration = new ConfigurePhase4();
        configuration.run();
        assertTrue(stack.performance.hasRole(stack.performance.CREATOR_ROLE(), creator));
        assertTrue(stack.performance.supportedTokens(address(0)));
        vm.setEnv("BARO_ADMIN_ADDRESS", vm.toString(deployer));
        vm.expectRevert("Wrong admin");
        configuration.run();
        vm.setEnv("BARO_ADMIN_ADDRESS", vm.toString(admin));
        vm.setEnv("BARO_CAMPAIGN_CREATOR", vm.toString(address(0)));
        vm.expectRevert("Missing creator");
        configuration.run();
        vm.setEnv("BARO_INDEX_ORACLE", vm.toString(address(stack.oracle)));
        vm.setEnv("BARO_INDEX_DAY", "20000");
        vm.setEnv("BARO_FEAR_GREED", "50");
        vm.setEnv("BARO_PROJECT_ROOT", vm.toString(keccak256("root")));
        vm.setEnv("BARO_SOURCE_HASH", vm.toString(keccak256("source")));
        PublishIndex publisher = new PublishIndex();
        assertTrue(publisher.run());
        assertFalse(publisher.run());
        assertEq(stack.oracle.snapshotCount(), 1);
        vm.setEnv("BARO_FEAR_GREED", "51");
        vm.expectRevert("Snapshot conflict");
        publisher.run();
        vm.chainId(1);
        vm.expectRevert("Wrong chain");
        publisher.run();
        vm.expectRevert("Wrong chain");
        configuration.run();
        vm.expectRevert("Wrong chain");
        deployment.run();
    }
}
