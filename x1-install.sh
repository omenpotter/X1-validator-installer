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
    print_color "info" "Creating stake account with $stake_amount SOL."

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

# Section 10: Validator Startup Configuration
print_color "info" "\n===== 10/10: Validator Startup Configuration ====="

# Create validator startup script
VALIDATOR_SCRIPT="$install_dir/start-validator.sh"

# Create the startup script with proper settings and output logging
cat > "$VALIDATOR_SCRIPT" << 'EOF'
#!/bin/bash

# Source environment variables
export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"

# Set ulimit
ulimit -n 1000000

# Create ledger directory if it doesn't exist
LEDGER_DIR="$HOME/x1_validator/ledger"
mkdir -p "$LEDGER_DIR"

# Create log directory
LOG_DIR="$HOME/x1_validator/logs"
mkdir -p "$LOG_DIR"

# Start the validator with output logging
exec solana-validator \
  --identity "$HOME/x1_validator/identity.json" \
  --vote-account "$HOME/x1_validator/vote.json" \
  --ledger "$LEDGER_DIR" \
  --rpc-port 8899 \
  --entrypoint 216.202.227.220:8001 \
  --full-rpc-api \
  --log "$LOG_DIR/validator.log" \
  --max-genesis-archive-unpacked-size 1073741824 \
  --no-incremental-snapshots \
  --require-tower \
  --enable-rpc-transaction-history \
  --enable-extended-tx-metadata-storage \
  --skip-startup-ledger-verification \
  --no-poh-speed-test \
  --bind-address 0.0.0.0 \
  --private-rpc \
  --dynamic-port-range 8000-8020 \
  --wal-recovery-mode skip_any_corrupted_record 2>&1 | tee -a "$LOG_DIR/validator.log"
EOF

# Make the script executable
chmod +x "$VALIDATOR_SCRIPT"

# Create systemd service file with enhanced logging
sudo tee /etc/systemd/system/solana-validator.service > /dev/null << EOF
[Unit]
Description=Solana Validator
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=$USER
LimitNOFILE=1000000
Environment="PATH=$PATH:/home/$USER/.local/share/solana/install/active_release/bin"
ExecStart=/bin/bash -c '$VALIDATOR_SCRIPT'
StandardOutput=append:$HOME/x1_validator/logs/validator.log
StandardError=append:$HOME/x1_validator/logs/validator.log

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
sudo systemctl daemon-reload

print_color "prompt" "\nDo you want to start the validator and delegate stake now? [y/n]"
read start_choice

if [ "$start_choice" == "y" ]; then
    print_color "info" "Preparing validator startup..."
    
    # Switch to identity keypair for delegation
    solana config set --keypair "$install_dir/identity.json" > /dev/null 2>&1
    
    # Get public keys
    identity_pubkey=$(solana-keygen pubkey "$install_dir/identity.json")
    vote_pubkey=$(solana-keygen pubkey "$install_dir/vote.json")
    stake_pubkey=$(solana-keygen pubkey "$install_dir/stake.json")
    
    print_color "info" "Checking account balances..."
    identity_balance=$(solana balance "$identity_pubkey")
    stake_balance=$(solana balance "$stake_pubkey")
    
    print_color "info" "Identity balance: $identity_balance SOL"
    print_color "info" "Stake account balance: $stake_balance SOL"
    
    # Check if stake is already delegated
    print_color "info" "Checking stake delegation status..."
    stake_status=$(solana stake-account "$stake_pubkey" 2>/dev/null)
    
    if ! echo "$stake_status" | grep -q "Delegated Vote Account Address"; then
        print_color "info" "Delegating stake to vote account..."
        
        # Delegate stake
        delegation_output=$(solana delegate-stake \
            --fee-payer "$install_dir/identity.json" \
            "$install_dir/stake.json" \
            "$vote_pubkey" 2>&1)
        
        if [ $? -eq 0 ]; then
            print_color "success" "Stake successfully delegated to vote account"
        else
            print_color "error" "Failed to delegate stake: $delegation_output"
            print_color "error" "Please check your account balances and try again"
            exit 1
        fi
        
        # Wait for delegation to be confirmed
        print_color "info" "Waiting for stake delegation to be confirmed..."
        sleep 10
    else
        print_color "success" "Stake is already delegated to vote account"
    fi
    
    # Verify delegation
    stake_info=$(solana stake-account "$stake_pubkey")
    print_color "info" "Stake account status:"
    echo "$stake_info"
    
    # Start the validator
    print_color "info" "Starting validator..."
    print_color "info" "Real-time validator output will be displayed below. Press Ctrl+C to stop viewing the output (validator will continue running in background)."
    print_color "info" "Starting in 5 seconds..."
    sleep 5
    
    # Start the validator in the background
    sudo systemctl enable solana-validator
