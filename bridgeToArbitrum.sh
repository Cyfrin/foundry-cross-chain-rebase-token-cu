#!/bin/bash

# Define constants 
AMOUNT=100000

DEFAULT_ARBITRUM_LOCAL_KEY="0x7726827caac94a7f9e1b160f7ea819f172f7b6f9d2a97f992c38edeab82d4110"
DEFAULT_ARBITRUM_ADDRESS="0x36615Cf349d7F6344891B1e7CA7C72883F5dc049"

ARBITRUM_REGISTRY_MODULE_OWNER_CUSTOM="0xE625ccfcF6Aa402d9d67EE5b82A1208Af8C0cf69"
ARBITRUM_TOKEN_ADMIN_REGISTRY="0x8126D8EAAd8EBAD5e831E0b47A8d0E80b0E57dc6"
ARBITRUM_ROUTER="0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165"
ARBITRUM_RNM_PROXY_ADDRESS="0x9527E2d01A3064ef6b50c1Da1C0C982977856CFF2"
ARBITRUM_SEPOLIA_CHAIN_SELECTOR="3478487238524512106"
ARBITRUM_LINK_ADDRESS="0xb1D4538B4571d411F07960EF2838Ce337FE1E80E"

SEPOLIA_REGISTRY_MODULE_OWNER_CUSTOM="0x62e731218d0D47305aba2BE3751E7EE9E5520790"
SEPOLIA_TOKEN_ADMIN_REGISTRY="0x95F29FEE11c5C55d26cCcf1DB6772DE953B37B82"
SEPOLIA_ROUTER="0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59"
SEPOLIA_RNM_PROXY_ADDRESS="0xba3f6251de62dED61Ff98590cB2fDf6871FbB991"
SEPOLIA_CHAIN_SELECTOR="16015286601757825753"
SEPOLIA_LINK_ADDRESS="0x779877A7B0D9E8603169DdbD7836e478b4624789"

# 1. Deploy on Arbitrum using scripts (like Sepolia)
source .env
forge build
echo "Running the script to deploy the contracts on Arbitrum..."
output=$(forge script ./script/Deployer.s.sol:TokenAndPoolDeployer --rpc-url ${ARBITRUM_SEPOLIA_RPC_URL} --account updraft --broadcast)
echo "Contracts deployed and permission set on Arbitrum"

# Extract the addresses from the output
ARBITRUM_REBASE_TOKEN_ADDRESS=$(echo "$output" | grep 'token: contract RebaseToken' | awk '{print $4}')
ARBITRUM_POOL_ADDRESS=$(echo "$output" | grep 'pool: contract RebaseTokenPool' | awk '{print $4}')

echo "Arbitrum rebase token address: $ARBITRUM_REBASE_TOKEN_ADDRESS"
echo "Arbitrum pool address: $ARBITRUM_POOL_ADDRESS"

# 2. Deploy on Sepolia
echo "Running the script to deploy the contracts on Sepolia..."
output=$(forge script ./script/Deployer.s.sol:TokenAndPoolDeployer --rpc-url ${SEPOLIA_RPC_URL} --account updraft --broadcast)
echo "Contracts deployed and permission set on Sepolia"

# Extract the addresses from the output
SEPOLIA_REBASE_TOKEN_ADDRESS=$(echo "$output" | grep 'token: contract RebaseToken' | awk '{print $4}')
SEPOLIA_POOL_ADDRESS=$(echo "$output" | grep 'pool: contract RebaseTokenPool' | awk '{print $4}')

echo "Sepolia rebase token address: $SEPOLIA_REBASE_TOKEN_ADDRESS"
echo "Sepolia pool address: $SEPOLIA_POOL_ADDRESS"

# Deploy the vault on Sepolia
echo "Deploying the vault on Sepolia..."
VAULT_ADDRESS=$(forge script ./script/Deployer.s.sol:VaultDeployer --rpc-url ${SEPOLIA_RPC_URL} --account updraft --broadcast --sig "run(address)" ${SEPOLIA_REBASE_TOKEN_ADDRESS} | grep 'vault: contract Vault' | awk '{print $NF}')
echo "Vault address: $VAULT_ADDRESS"

# Configure the pool on Sepolia
echo "Configuring the pool on Sepolia..."
# uint64 remoteChainSelector,
#         address remotePoolAddress, 
#         address remoteTokenAddress, 
#         bool outboundRateLimiterIsEnabled, false 
#         uint128 outboundRateLimiterCapacity, 0
#         uint128 outboundRateLimiterRate, 0
#         bool inboundRateLimiterIsEnabled, false 
#         uint128 inboundRateLimiterCapacity, 0 
#         uint128 inboundRateLimiterRate 0 
forge script ./script/ConfigurePool.s.sol:ConfigurePoolScript --rpc-url ${SEPOLIA_RPC_URL} --account updraft --broadcast --sig "run(address,uint64,address,address,bool,uint128,uint128,bool,uint128,uint128)" ${SEPOLIA_POOL_ADDRESS} ${ARBITRUM_SEPOLIA_CHAIN_SELECTOR} ${ARBITRUM_POOL_ADDRESS} ${ARBITRUM_REBASE_TOKEN_ADDRESS} false 0 0 false 0 0

# Deposit funds to the vault
echo "Depositing funds to the vault on Sepolia..."
cast send ${VAULT_ADDRESS} --value ${AMOUNT} --rpc-url ${SEPOLIA_RPC_URL} --account updraft "deposit()"

# Wait a beat for some interest to accrue

# Configure the pool on Arbitrum
echo "Configuring the pool on Arbitrum..."
forge script ./script/ConfigurePool.s.sol:ConfigurePoolScript --rpc-url ${ARBITRUM_SEPOLIA_RPC_URL} --account updraft --broadcast --sig "run(address,uint64,address,address,bool,uint128,uint128,bool,uint128,uint128)" ${ARBITRUM_POOL_ADDRESS} ${SEPOLIA_CHAIN_SELECTOR} ${SEPOLIA_POOL_ADDRESS} ${SEPOLIA_REBASE_TOKEN_ADDRESS} false 0 0 false 0 0

# Bridge the funds using the script to Arbitrum 
echo "Bridging the funds using the script to Arbitrum..."
SEPOLIA_BALANCE_BEFORE=$(cast balance $(cast wallet address --account updraft) --erc20 ${SEPOLIA_REBASE_TOKEN_ADDRESS} --rpc-url ${SEPOLIA_RPC_URL})
echo "Sepolia balance before bridging: $SEPOLIA_BALANCE_BEFORE"
forge script ./script/BridgeTokens.s.sol:BridgeTokensScript --rpc-url ${SEPOLIA_RPC_URL} --account updraft --broadcast --sig "run(address,uint64,address,uint256,address,address)" $(cast wallet address --account updraft) ${ARBITRUM_SEPOLIA_CHAIN_SELECTOR} ${SEPOLIA_REBASE_TOKEN_ADDRESS} ${AMOUNT} ${SEPOLIA_LINK_ADDRESS} ${SEPOLIA_ROUTER}
echo "Funds bridged to Arbitrum"
SEPOLIA_BALANCE_AFTER=$(cast balance $(cast wallet address --account updraft) --erc20 ${SEPOLIA_REBASE_TOKEN_ADDRESS} --rpc-url ${SEPOLIA_RPC_URL})
echo "Sepolia balance after bridging: $SEPOLIA_BALANCE_AFTER" 