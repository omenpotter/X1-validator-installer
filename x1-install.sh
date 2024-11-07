#!/bin/bash

# Function to print color-coded messages with timestamp
function print_color {
    timestamp=$(date '+%H:%M:%S')
    case $1 in
        "info")
            echo -e "[$timestamp] \033[1;34m$2\033[0m"  # Blue for informational
            ;;
        "success")
            echo -e "[$timestamp] \033[1;32m$2\033[0m"  # Green for success
            ;;
        "error")
            echo -e "[$timestamp] \033[1;31m$2\033[0m"  # Red for errors
            ;;
        "prompt")
            echo -e "[$timestamp] \033[1;33m$2\033[0m"  # Yellow for user prompts
            ;;
        "progress")
            echo -e "[$timestamp] \033[1;36m$2\033[0m"  # Cyan for progress
            ;;
    esac
}

# Function to display progress
function show_progress() {
    local duration=$1
    local step_size=1
    local progress=0
    local width=50

    while [ $progress -lt $duration ]; do
        echo -ne "\r["
        local current=$((progress * width / duration))
        local remainder=$((width - current))
        printf "#%.0s" $(seq 1 $current)
        printf " %.0s" $(seq 1 $remainder)
        echo -ne "] $((progress * 100 / duration))%"
        progress=$((progress + step_size))
        sleep 1
    done
    echo -ne "\r[$(printf "#%.0s" $(seq 1 $width))] 100%\n"
}

# Display script header
clear
print_color "info" "==============================================="
print_color "info" "     X1 Participating Validator Setup Script    "
print_color "info" "==============================================="
print_color "info" "This script will show detailed progress of each step"
print_color "info" "Please wait for each step to complete..."
echo ""

# Section 1: Setup Validator Directory
print_color "info" "\n===== Step 1/11: Validator Directory Setup ====="

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
        print_color "progress" "Removing existing directory..."
        rm -rf "$install_dir"
        print_color "success" "Deleted $install_dir"
    else
        print_color "error" "Please choose a different directory."
        exit 1
    fi
fi

mkdir -p "$install_dir"
cd "$install_dir" || exit 1
print_color "success" "Directory created and accessed: $install_dir"

# Section 2: Install Rust
print_color "info" "\n===== Step 2/11: Rust Installation ====="

if ! command -v rustc &> /dev/null; then
    print_color "progress" "Installing Rust... This may take a few minutes"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    print_color "success" "Rust installed: $(rustc --version)"
else
    print_color "success" "Rust is already installed: $(rustc --version)"
fi

# Section 3: Install Solana CLI
print_color "info" "\n===== Step 3/11: Solana CLI Installation ====="

print_color "progress" "Installing Solana CLI... This may take a few minutes"
sh -c "$(curl -sSfL https://release.solana.com/v1.18.25/install)"

# Add Solana to PATH and reload
if ! grep -q 'solana' ~/.profile; then
    echo 'export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"' >> ~/.profile
fi
export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
source ~/.profile

solana --version
print_color "success" "Solana CLI installed successfully"

# Section 4: Switch to Xolana Network
print_color "info" "\n===== Step 4/11: Switch to Xolana Network ====="

print_color "progress" "Configuring Xolana network..."
solana config set -u http://xolana.xen.network:8899
network_url=$(solana config get | grep 'RPC URL' | awk '{print $NF}')
print_color "success" "Network configuration:"
solana config get

# Section 5: Wallets Creation
print_color "info" "\n===== Step 5/11: Creating Wallets ====="

print_color "progress" "Creating identity wallet..."
solana-keygen new --no-passphrase --outfile $install_dir/identity.json
identity_pubkey=$(solana-keygen pubkey $install_dir/identity.json)

print_color "progress" "Creating vote wallet..."
solana-keygen new --no-passphrase --outfile $install_dir/vote.json
vote_pubkey=$(solana-keygen pubkey $install_dir/vote.json)

print_color "progress" "Creating stake wallet..."
solana-keygen new --no-passphrase --outfile $install_dir/stake.json
stake_pubkey=$(solana-keygen pubkey $install_dir/stake.json)

print_color "progress" "Creating withdrawer wallet..."
solana-keygen new --no-passphrase --outfile $HOME/.config/solana/withdrawer.json
withdrawer_pubkey=$(solana-keygen pubkey $HOME/.config/solana/withdrawer.json)

# Display wallet information
print_color "success" "Wallets created successfully!"
print_color "error" "********************************************************"
print_color "info" "Identity Wallet Address: $identity_pubkey"
print_color "info" "Vote Wallet Address: $vote_pubkey"
print_color "info" "Stake Wallet Address: $stake_pubkey"
print_color "info" "Withdrawer Public Key: $withdrawer_pubkey"
print_color "info" " "
print_color "info" "Private keys are stored in:"
print_color "info" "Identity: $install_dir/identity.json"
print_color "info" "Vote: $install_dir/vote.json"
print_color "info" "Stake: $install_dir/stake.json"
print_color "info" "Withdrawer: $HOME/.config/solana/withdrawer.json"
print_color "error" "********************************************************"
print_color "prompt" "IMPORTANT: Save these addresses and key locations securely!"
print_color "prompt" "Press Enter to continue..."
read

# Section 6: Request Faucet Funds
print_color "info" "\n===== Step 6/11: Requesting Faucet Funds ====="

request_faucet() {
    local attempt=1
    while [ $attempt -le 3 ]; do
        print_color "progress" "Attempting to request funds (attempt $attempt/3)..."
        response=$(curl -s -X POST -H "Content-Type: application/json" -d "{\"pubkey\":\"$1\"}" https://xolana.xen.network/faucet)
        
        if echo "$response" | grep -q "Please wait"; then
            wait_time=$(echo "$response" | sed -n 's/.*Please wait \([0-9]*\) minutes.*/\1/p')
            wait_time=$((wait_time + 1))
            print_color "progress" "Faucet cooldown: Waiting $wait_time minutes..."
            show_progress $((wait_time * 60))
        elif echo "$response" | grep -q '"success":true'; then
            print_color "success" "Successfully requested 5 SOL"
            return 0
        else
            print_color "error" "Attempt $attempt failed. Response: $response"
            attempt=$((attempt + 1))
            sleep 5
        fi
    done
    return 1
}

request_faucet $identity_pubkey
print_color "progress" "Waiting 30 seconds to verify balance..."
show_progress 30

balance=$(solana balance $identity_pubkey)
print_color "info" "Current balance: $balance"

# Section 7: Set Default Keypair
print_color "info" "\n===== Step 7/11: Setting Default Keypair ====="
solana config set --keypair $install_dir/identity.json
print_color "success" "Default keypair configured"

# Section 8: Create Vote Account
print_color "info" "\n===== Step 8/11: Creating Vote Account ====="
print_color "prompt" "Enter commission percentage (default: 10):"
read commission
commission=${commission:-10}

print_color "progress" "Creating vote account with $commission% commission..."
# Temporarily switch to withdrawer key
solana config set --keypair $HOME/.config/solana/withdrawer.json
solana create-vote-account $install_dir/vote.json $install_dir/identity.json $withdrawer_pubkey --commission $commission

# Reset to identity key
solana config set --keypair $install_dir/identity.json
print_color "success" "Vote account created and configured"

# Section 9: Create and Delegate Stake
print_color "info" "\n===== Step 9/11: Creating and Delegating Stake ====="

balance=$(solana balance $identity_pubkey)
print_color "info" "Current balance: $balance"

print_color "progress" "Creating stake account with 2 SOL..."
solana create-stake-account $install_dir/stake.json 2

print_color "progress" "Delegating stake to vote account..."
solana delegate-stake $install_dir/stake.json $install_dir/vote.json
print_color "success" "Stake account created and delegated"

# Section 10: System Tuning
print_color "info" "\n===== Step 10/11: System Tuning ====="
print_color "progress" "Configuring system parameters..."

sudo bash -c "cat >/etc/sysctl.d/21-solana-validator.conf <<EOF
net.core.rmem_default = 134217728
net.core.rmem_max = 134217728
net.core.wmem_default = 134217728
net.core.wmem_max = 134217728
vm.max_map_count = 1000000
fs.nr_open = 1000000
EOF"

print_color "progress" "Applying system parameters..."
sudo sysctl -p /etc/sysctl.d/21-solana-validator.conf

ulimit -n 1000000
print_color "success" "System tuning completed"

# Section 11: Final Instructions
print_color "info" "\n===== Step 11/11: Setup Complete ====="
print_color "success" "X1 Participating Validator setup completed successfully!"
print_color "info" "\nTo start your validator, run the following command:"
print_color "prompt" "\nexport PATH=\"\$HOME/.local/share/solana/install/active_release/bin:\$PATH\"; ulimit -n 1000000; solana-validator \
    --identity $install_dir/identity.json \
    --vote-account $install_dir/vote.json \
    --rpc-port 8899 \
    --entrypoint 216.202.227.220:8001 \
    --full-rpc-api \
    --log - \
    --max-genesis-archive-unpacked-size 1073741824 \
    --no-incremental-snapshots \
    --require-tower \
    --enable-rpc-transaction-history \
    --enable-extended-tx-metadata-storage \
    --skip-startup-ledger-verification \
    --no-poh-speed-test \
    --bind-address 0.0.0.0"

print_color "info" "\nIMPORTANT: Save your keys and addresses from Step 5 before proceeding!"
print_color "info" "Setup completed at: $(date)"
print_color "info" "\n\n"
