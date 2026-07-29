.PHONY: check simulate-giwa deploy-giwa

check:
	forge clean
	forge fmt --check
	forge lint
	forge build --sizes
	forge test -vvv
	./scripts/check-coverage.sh

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
