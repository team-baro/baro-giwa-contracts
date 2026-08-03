// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";

import { BaroCampaignEscrow } from "../src/BaroCampaignEscrow.sol";
import { BaroQuestTestToken } from "../src/BaroQuestTestToken.sol";
import { BaroReputationSBT } from "../src/BaroReputationSBT.sol";
import { IBaroReputationSBT } from "../src/interfaces/IBaroReputationSBT.sol";

contract DeployGIWASepolia is Script {
    uint256 private constant GIWA_SEPOLIA_CHAIN_ID = 91_342;

    function run()
        external
        returns (
            BaroCampaignEscrow escrow,
            BaroReputationSBT reputation,
            BaroQuestTestToken rewardToken
        )
    {
        require(block.chainid == GIWA_SEPOLIA_CHAIN_ID, "Wrong chain");
        address deployer = vm.envAddress("BARO_DEPLOYER_ADDRESS");
        address admin = vm.envAddress("BARO_ADMIN_ADDRESS");
        address operator = vm.envAddress("BARO_OPERATOR_ADDRESS");
        address projectOwner = vm.envOr("BARO_PROJECT_OWNER_ADDRESS", deployer);
        string memory baseTokenURI = vm.envOr("BARO_SBT_BASE_URI", string(""));
        uint256 testTokenSupply = vm.envOr("BARO_TEST_TOKEN_SUPPLY", uint256(25_000 ether));
        address predictedReputation = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);

        vm.startBroadcast(deployer);
        escrow = new BaroCampaignEscrow(admin, operator, IBaroReputationSBT(predictedReputation));
        reputation = new BaroReputationSBT(admin, operator, address(escrow), baseTokenURI);
        rewardToken = new BaroQuestTestToken(projectOwner, testTokenSupply);
        vm.stopBroadcast();

        require(address(reputation) == predictedReputation, "Unexpected reputation address");
        require(escrow.defaultAdmin() == admin, "Wrong escrow admin");
        require(reputation.defaultAdmin() == admin, "Wrong reputation admin");
        require(escrow.hasRole(escrow.OPERATOR_ROLE(), operator), "Missing escrow operator");
        require(reputation.hasRole(reputation.OPERATOR_ROLE(), operator), "Missing SBT operator");
        require(
            reputation.hasRole(reputation.ESCROW_ROLE(), address(escrow)), "Missing escrow role"
        );
        require(rewardToken.balanceOf(projectOwner) == testTokenSupply, "Wrong test token supply");
    }
}
