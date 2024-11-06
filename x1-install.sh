#!/bin/bash

# Function to print color-coded messages
function print_color {
    case $1 in
        "info")
            echo -e "\033[1;34m$2\033[0m"  # Blue for informational
            ;;
        "success")
            echo -e "\033[1;32m$2\033[0m"  # Green for success
            ;;
        "error")
            echo -e "\033[1;31m$2\033[0m"  # Red for errors
            ;;
        "prompt")
            echo -e "\033[1;33m$2\033[0m"  # Yellow for user prompts
            ;;
    esac
}

# Section 1: Setup Validator Directory
print_color "info" "\n"
print_color "info" "\n===== 1/10: Validator Directory Setup ====="

default_install_dir="$HOME/x1_validator"
print_color "prompt" "Validator Directory (press Enter for default: $default_install_dir):"
read install_dir

if [ -z "$install_dir" ]; then
    install_dir=$default_install_dir
fi

if [ -d "$install_dir" ]; then
    print_color "prompt" "Directory exists. Delete it? [y/n]"
    read choice
    if [ "$choice" == "y" ]; then
        rm -rf "$install_dir" > /dev/null 2>&1
        print_color "info" "Deleted $install_dir"
    else
        print_color "error" "Please choose a different directory."
        exit 1
    fi
fi

mkdir -p "$install_dir" > /dev/null 2>&1
cd "$install_dir" || exit 1
print_color "success" "Directory created: $install_dir"


# Section 2: Install Rust
print_color "info" "\n===== 2/10: Rust Installation ====="

if ! command -v rustc &> /dev/null; then
    print_color "info" "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y > /dev/null 2>&1
    source "$HOME/.cargo/env" > /dev/null 2>&1
else
    print_color "success" "Rust is already installed: $(rustc --version)"
fi
print_color "success" "Rust installed."

# Section 3: Install Solana CLI
print_color "info" "\n===== 3/10: Solana CLI Installation ====="

print_color "info" "Installing Solana CLI..."
sh -c "$(curl -sSfL https://release.solana.com/v1.18.25/install)" > /dev/null 2>&1 || {
    print_color "error" "Solana CLI installation failed."
    exit 1
}

# Add Solana to PATH and reload
if ! grep -q 'solana' ~/.profile; then
    echo 'export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"' >> ~/.profile
fi
export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH" > /dev/null 2>&1
print_color "success" "Solana CLI installed."

# Source the profile to update the current shell
source ~/.profile

# Section 4: Switch to Xolana Network
print_color "info" "\n===== 4/10: Switch to Xolana Network ====="

solana config set -u http://xolana.xen.network:8899 > /dev/null 2>&1
network_url=$(solana config get | grep 'RPC URL' | awk '{print $NF}')
if [ "$network_url" != "http://xolana.xen.network:8899" ]; then
    print_color "error" "Failed to switch to Xolana network."
    exit 1
fi
print_color "success" "Switched to Xolana network."

# Section 5: Wallets Creation
print_color "info" "\n===== 5/10: Creating Wallets ====="

solana-keygen new --no-passphrase --outfile $install_dir/identity.json > /dev/null 2>&1
identity_pubkey=$(solana-keygen pubkey $install_dir/identity.json)

solana-keygen new --no-passphrase --outfile $install_dir/vote.json > /dev/null 2>&1
vote_pubkey=$(solana-keygen pubkey $install_dir/vote.json)

solana-keygen new --no-passphrase --outfile $install_dir/stake.json > /dev/null 2>&1
stake_pubkey=$(solana-keygen pubkey $install_dir/stake.json)

solana-keygen new --no-passphrase --outfile $HOME/.config/solana/withdrawer.json > /dev/null 2>&1
withdrawer_pubkey=$(solana-keygen pubkey $HOME/.config/solana/withdrawer.json)

# Output wallet information
print_color "success" "Wallets created successfully!"
print_color "error" "********************************************************"
print_color "info" "Identity Wallet Address: $identity_pubkey"
print_color "info" "Vote Wallet Address: $vote_pubkey"
print_color "info" "Stake Wallet Address: $stake_pubkey"
print_color "info" "Withdrawer Public Key: $withdrawer_pubkey"
print_color "info" " "
print_color "info" "Private keys are stored in the following locations:"
print_color "info" "Identity Private Key: $install_dir/identity.json"
print_color "info" "Vote Private Key: $install_dir/vote.json"
print_color "info" "Stake Private Key: $install_dir/stake.json"
print_color "info" "Withdrawer Private Key: $HOME/.config/solana/withdrawer.json"
print_color "error" "********************************************************"
print_color "prompt" "IMPORTANT: After installation, make sure to save both the public addresses and private key files listed above in a secure location!"

# Section 6: Request Faucet Funds
print_color "info" "\n===== 6/10: Requesting Faucet Funds ====="

request_faucet() {
    response=$(curl -s -X POST -H "Content-Type: application/json" -d "{\"pubkey\":\"$1\", \"amount\": 5}" https://xolana.xen.network/faucet)
    if echo "$response" | grep -q "Please wait"; then
        wait_message=$(echo "$response" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p')
        print_color "error" "Faucet request failed: $wait_message"
    elif echo "$response" | grep -q '"success":true'; then
        print_color "success" "5 SOL requested successfully."
    else
        print_color "error" "Faucet request failed. Response: $response"
    fi
}

request_faucet $identity_pubkey
print_color "info" "Waiting 30 seconds to verify balance..."
sleep 30

balance=$(solana balance $identity_pubkey | awk '{print $1}')
if (( $(echo "$balance > 0" | bc -l) )); then
    print_color "success" "Identity funded with $balance SOL."
else
    print_color "error" "Failed to get SOL. Exiting."
    exit 1
fi

# Set default keypair to identity keypair
print_color "info" "Setting default keypair to identity keypair..."
solana config set --keypair $install_dir/identity.json

# Section 7: Create Vote Account with Commission 5%
print_color "info" "\n===== 7/10: Creating Vote Account ====="

vote_amount=1.5  # Fixed amount for vote account

if (( $(echo "$balance >= $vote_amount" | bc -l) )); then
    solana create-vote-account $install_dir/vote.json $install_dir/identity.json $withdrawer_pubkey --commission 5
    if [ $? -eq 0 ]; then
        print_color "success" "Vote account created with 5% commission."
    else
        print_color "error" "Failed to create vote account."
        exit 1
    fi

    # Check balance after creating vote account
    balance=$(solana balance $identity_pubkey | awk '{print $1}')
    print_color "info" "Balance after creating vote account: $balance SOL"
else
    print_color "error" "Insufficient funds to create vote account."
    exit 1
fi

# Section 8: Create and Fund Stake Account
print_color "info" "\n===== 8/10: Creating Stake Account ====="

stake_amount=1.5  # Fixed amount for stake account

if (( $(echo "$balance >= $stake_amount" | bc -l) )); then
    print_color "info" "Staking $stake_amount SOL."

    solana create-stake-account $install_dir/stake.json $stake_amount
    if [ $? -eq 0 ]; then
        print_color "success" "Stake account created and funded with $stake_amount SOL."
    else
        print_color "error" "Failed to create and fund stake account."
        exit 1
    fi
else
    print_color "error" "Insufficient funds to create stake account."
    exit 1
fi

# Section 9: System Tuning
print_color "info" "\n===== 9/10: System Tuning ====="
print_color "info" "If needed, please provide admin password for system tuning."

sudo bash -c "cat >/etc/sysctl.d/21-solana-validator.conf <<EOF
net.core.rmem_default = 134217728
net.core.rmem_max = 134217728
net.core.wmem_default = 134217728
net.core.wmem_max = 134217728
vm.max_map_count = 1000000
fs.nr_open = 1000000
EOF"
sudo sysctl -p /etc/sysctl.d/21-solana-validator.conf

# Set ulimit for current session
ulimit -n 1000000

# Ensure Solana CLI is in PATH
export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"

print_color "success" "System tuned for validator performance."

# Section 10: Create and Start Validator Service
print_color "info" "\n===== 10/10: Finished ====="

# Set the installation directory
install_dir="$HOME/x1_validator"
mkdir -p "$install_dir"

# Check for required keypairs
print_color "info" "Checking for required keypairs..."
if [ ! -f "$install_dir/identity.json" ] || [ ! -f "$install_dir/vote.json" ] || [ ! -f "$install_dir/stake.json" ]; then
    print_color "error" "Required keypair files not found in $install_dir. Exiting."
    exit 1
fi
print_color "success" "All keypair files are present."

# Set the default keypair to identity keypair
print_color "info" "Setting default keypair to identity keypair..."
solana config set --keypair "$install_dir/identity.json"

# Get the public key of the withdrawer wallet
withdrawer_pubkey=$(solana address -k "$HOME/.config/solana/withdrawer.json")

# Fund the withdrawer wallet with 1.5 SOL from the identity wallet
print_color "info" "Funding withdrawer wallet with 1.5 SOL from identity wallet..."
transfer_output=$(solana transfer "$withdrawer_pubkey" 1.5 --from "$install_dir/identity.json" --allow-unfunded-recipient --fee-payer "$install_dir/identity.json" 2>&1)
if [ $? -ne 0 ]; then
    print_color "error" "Failed to transfer 1.5 SOL from the identity wallet: $transfer_output"
    exit 1
fi

# Set Solana CLI to use withdrawer keypair
print_color "info" "Configuring Solana CLI to use the withdrawer keypair..."
solana config set -k "$HOME/.config/solana/withdrawer.json"
if [ $? -eq 0 ]; then
    print_color "success" "Switched to withdrawer keypair."
else
    print_color "error" "Failed to switch to withdrawer keypair."
    exit 1
fi

# Call the function to check the balance

# Verify if the transfer was successful
print_color "info" "Waiting 30 seconds to confirm funds in withdrawer wallet..."
sleep 30
balance=$(solana balance "$withdrawer_pubkey" | awk '{print $1}')

# Verify that the balance is a valid number
if [[ $balance =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    # Check if the balance is greater than or equal to 1.5 SOL
    if (( $(echo "$balance >= 1.5" | bc -l) )); then
        print_color "success" "Withdrawer wallet funded with $balance SOL."
    else
        print_color "error" "Failed to get 1.5 SOL in the withdrawer wallet. Current balance is $balance SOL."
        exit 1
    fi
else
    print_color "error" "Error: Unable to fetch a valid balance. Current output: $balance"
    exit 1
fi

# Change directory to validator installation directory
cd "$install_dir"

# Delegate the stake
print_color "info" "Delegating the stake to the vote account..."

# Check if the vote.json file exists
if [ -f "$install_dir/vote.json" ]; then
    print_color "info" "Found vote.json file."
else
    print_color "error" "vote.json file not found in $install_dir. Exiting."
    exit 1
fi

# Extract the public key from the vote.json file
vote_pubkey=$(solana-keygen pubkey "$install_dir/vote.json")

# Check if the public key was extracted successfully
if [ -z "$vote_pubkey" ]; then
    print_color "error" "Failed to extract the vote account public key. Exiting."
    exit 1
else
    print_color "info" "Vote account public key: $vote_pubkey"
fi

# Delegate the stake using the vote account public key
solana delegate-stake "$install_dir/stake.json" "$vote_pubkey"

# Check if the delegation was successful
if [ $? -eq 0 ]; then
    print_color "success" "Stake successfully delegated."
else
    print_color "error" "Failed to delegate stake."
    exit 1
fi


# Switch RPC URL to the new endpoint
print_color "info" "Setting Solana CLI to use the new RPC endpoint..."
solana config set -u https://xolana.xen.network
network_url=$(solana config get | grep 'RPC URL' | awk '{print $NF}')
if [ "$network_url" == "https://xolana.xen.network" ]; then
    print_color "success" "RPC URL set to $network_url."
else
    print_color "error" "Failed to set RPC URL."
    exit 1
fi

# Start the validator
print_color "info" "Starting the Solana validator..."
print_color "prompt" "Run the following command to start your validator:"
echo -e "\nexport PATH=\"\$HOME/.local/share/solana/install/active_release/bin:\$PATH\"; \\
ulimit -n 1000000; \\
solana-validator --identity $install_dir/identity.json --vote-account $install_dir/vote.json --rpc-port 8899 \\
--entrypoint 216.202.227.220:8001 --full-rpc-api --log - --max-genesis-archive-unpacked-size 1073741824 \\
--no-incremental-snapshots --require-tower --enable-rpc-transaction-history \\
--enable-extended-tx-metadata-storage --skip-startup-ledger-verification \\
--no-poh-speed-test --bind-address 0.0.0.0"

print_color "success" "Script execution completed. Validator setup is ready."

print_color "success" "\nX1 Validator setup complete!"
print_color "success" "\nStart your X1 Validator by using the following command:"
print_color "prompt" "\nexport PATH=\"\$HOME/.local/share/solana/install/active_release/bin:\$PATH\"; ulimit -n 1000000; solana-validator --identity $install_dir/identity.json --vote-account $install_dir/vote.json --rpc-port 8899 --entrypoint 216.202.227.220:8001 --full-rpc-api --log - --max-genesis-archive-unpacked-size 1073741824 --no-incremental-snapshots --require-tower --enable-rpc-transaction-history --enable-extended-tx-metadata-storage --skip-startup-ledger-verification --no-poh-speed-test --bind-address 0.0.0.0"
print_color "info" "\n\n\n"
