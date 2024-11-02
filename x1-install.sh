#!/bin/bash

# Set up environment variables
export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
export SOLANA_VALIDATOR_DIR="$HOME/x1_validator"
export SOLANA_CONFIG_DIR="$HOME/.config/solana"

# Create necessary directories
mkdir -p "$SOLANA_VALIDATOR_DIR"

# Initialize solana CLI config
solana config set --url https://api.mainnet-beta.solana.com
solana config set --keypair "$SOLANA_VALIDATOR_DIR/identity.json"

# Generate keypairs for identity, vote, and stake accounts
solana-keygen new --outfile "$SOLANA_VALIDATOR_DIR/identity.json" --no-bip39-passphrase
solana-keygen new --outfile "$SOLANA_VALIDATOR_DIR/vote.json" --no-bip39-passphrase
solana-keygen new --outfile "$SOLANA_VALIDATOR_DIR/stake.json" --no-bip39-passphrase

# Set up vote account with commission set to 10%
solana create-vote-account "$SOLANA_VALIDATOR_DIR/vote.json" "$SOLANA_VALIDATOR_DIR/identity.json" "$SOLANA_VALIDATOR_DIR/identity.json" --commission 10

# Fund the stake account and delegate to the vote account
solana create-stake-account "$SOLANA_VALIDATOR_DIR/stake.json" 100
solana delegate-stake "$SOLANA_VALIDATOR_DIR/stake.json" "$SOLANA_VALIDATOR_DIR/vote.json"

# New Section Start

# Switch to your withdrawer keypair
solana config set -k "$SOLANA_CONFIG_DIR/withdrawer.json"

# Enter the validator directory where wallets are stored
cd "$SOLANA_VALIDATOR_DIR"

# Fund 5 SOL to your withdrawer through the faucet
withdrawer_pubkey=$(solana-keygen pubkey "$SOLANA_CONFIG_DIR/withdrawer.json")
curl -s -X POST -H "Content-Type: application/json" -d "{\"pubkey\":\"$withdrawer_pubkey\"}" https://xolana.xen.network/web_faucet
echo "Waiting 30 seconds to confirm faucet funds..."
sleep 30

# Check balance to confirm funding
balance=$(solana balance "$withdrawer_pubkey" | awk '{print $1}')
if (( $(echo "$balance >= 5" | bc -l) )); then
    echo "Withdrawer wallet funded with $balance SOL."
else
    echo "Failed to get 5 SOL in the withdrawer wallet. Exiting."
    exit 1
fi

# Create the stake account with 2 SOL
solana create-stake-account "$SOLANA_VALIDATOR_DIR/stake.json" 2

# Create the vote account using withdrawer public key with 10% commission
solana create-vote-account "$SOLANA_VALIDATOR_DIR/vote.json" "$SOLANA_VALIDATOR_DIR/identity.json" "$withdrawer_pubkey" --commission 10

# Delegate the stake to the vote account
solana delegate-stake "$SOLANA_VALIDATOR_DIR/stake.json" "$SOLANA_VALIDATOR_DIR/vote.json"

# Change to new RPC URL
solana config set -u https://xolana.xen.network

# New Section End

# Start Solana validator
solana-validator --identity "$SOLANA_VALIDATOR_DIR/identity.json" --vote-account "$SOLANA_VALIDATOR_DIR/vote.json" \
--rpc-port 8899 --entrypoint mainnet-beta.solana.com:8001 --known-validator GDNJmohEeGUL2NZozoDXYLx5nvXezrL5FAwYtv1L9Wpj \
--known-validator DE1E5uWep3XYNGFbAJe8uD7js6V3X6esvLvxDqzDt47P --known-validator CakcnaRDH9Z8JDzLCp8duVy9j8mDzhT6h4KxXzQ7eCHz \
--dynamic-port-range 8000-8010 --no-untrusted-rpc --ledger "$SOLANA_VALIDATOR_DIR/ledger" --limit-ledger-size 50000000 \
--log - --full-rpc-api --snapshot-interval-slots 500 --account-index program-id --no-poh-speed-test
