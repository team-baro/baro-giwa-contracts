.PHONY: check simulate-giwa deploy-giwa test-fork simulate-phase4

check:
	forge clean
	forge fmt --check
	forge lint
	forge build --sizes
	forge test --force -vvv
	./scripts/check-coverage.sh
	PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s test/tooling -v
	python3 tools/export_integration.py --check

simulate-giwa:
	forge script script/DeployGIWASepolia.s.sol:DeployGIWASepolia \
		--rpc-url giwa_sepolia \
		--sender "$$BARO_DEPLOYER_ADDRESS"

deploy-giwa:
	forge script script/DeployGIWASepolia.s.sol:DeployGIWASepolia \
		--rpc-url giwa_sepolia \
		--sender "$$BARO_DEPLOYER_ADDRESS" \
		--account "$$DEPLOYER_ACCOUNT" \
		--broadcast \
		--verify \
		--verifier blockscout \
		--verifier-url "$$BLOCKSCOUT_API_URL"

# Read-only fork execution: all contract writes stay in the local test VM.
test-fork:
	BARO_RUN_FORK_TESTS=true forge test --match-contract GIWAPhase4ForkTest -vv

simulate-phase4:
	forge script script/DeployPhase4.s.sol:DeployPhase4 --rpc-url giwa_sepolia --sender "$$BARO_DEPLOYER_ADDRESS"
