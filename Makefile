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
		--rpc-url giwa_sepolia

deploy-giwa:
	forge script script/DeployGIWASepolia.s.sol:DeployGIWASepolia \
		--rpc-url giwa_sepolia \
		--broadcast \
		--verify \
		--verifier blockscout \
		--verifier-url "$$BLOCKSCOUT_API_URL"
