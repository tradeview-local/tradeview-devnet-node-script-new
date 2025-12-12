#!/bin/bash

# Check if the script is run as root
#if [ "$(id -u)" != "0" ]; then
#  echo "This script must be run as root or with sudo." 1>&2
#  exit 1
#fi
current_path=$(pwd)
bash  $current_path/install-go.sh 

source $HOME/.bashrc
ulimit -n 16384

go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.5.0
# Determine the path of cosmovisor
COSMOVISOR_PATH=$(which cosmovisor)
echo "Cosmovisor is installed at: $COSMOVISOR_PATH"

# Get OS and version
OS=$(awk -F '=' '/^NAME/{print $2}' /etc/os-release | awk '{print $1}' | tr -d '"')
VERSION=$(awk -F '=' '/^VERSION_ID/{print $2}' /etc/os-release | awk '{print $1}' | tr -d '"')



# Define the binary and installation paths
BINARY="tradeviewd"
INSTALL_PATH="/usr/local/bin/"                   #AWS
#  INSTALL_PATH="/root/go/bin/"                  #Huawei

# Check if the OS is Ubuntu and the version is either 22.04 or 24.04
if [ "$OS" == "Ubuntu" ] && [ "$VERSION" == "22.04" -o "$VERSION" == "24.04" ]; then
  # Copy and set executable permissions
  current_path=$(pwd)
  
  # Update package lists and install necessary packages
  sudo  apt-get update
  sudo apt-get install -y build-essential jq wget unzip
  
  # Check if the installation path exists
  if [ -d "$INSTALL_PATH" ]; then

# --- Binary Download Logic ---
# Detect Ubuntu version for choosing the matching prebuilt binary
# UBUNTU_VERSION=$(lsb_release -rs)
# Set binary download URL (update this if your release URL pattern is different)
BINARY_URL="https://github.com/tradeview-local/tradeview-devnet-node-script-new/releases/download/ubuntu${VERSION}/${BINARY}"
echo $BINARY_URL

# Download and install the node binary into the chosen install path
echo "Downloading binary for Ubuntu $UBUNTU_VERSION: $BINARY_URL"
curl -L "$BINARY_URL" -o "/tmp/${BINARY}"
chmod +x "/tmp/${BINARY}"
sudo cp "/tmp/${BINARY}" "$INSTALL_PATH"
echo "Binary moved to ${INSTALL_PATH}${BINARY}"
sudo chmod +x "${INSTALL_PATH}${BINARY}"
  # sudo  cp "$current_path/ubuntu${VERSION}build/$BINARY" "$INSTALL_PATH" && sudo chmod +x "${INSTALL_PATH}${BINARY}"
    echo "$BINARY installed or updated successfully!"
  else
    echo "Installation path $INSTALL_PATH does not exist. Please create it."
    exit 1
  fi
else
  echo "Please check the OS version support; at this time, only Ubuntu 20.04 and 22.04 are supported."
  exit 1
fi


#==========================================================================================================================================
echo "============================================================================================================"
echo "Enter the Name for the node:"
echo "============================================================================================================"
read -r MONIKER
KEYS="val1"
CHAINID="${CHAIN_ID:-tradeview_9092-1}"
KEYRING="os"
KEYALGO="eth_secp256k1"
LOGLEVEL="info"

# Set dedicated home directory for the tradeviewd instance
 HOMEDIR="/data/.tmp-tradeviewd"


# Check if the service is running
if systemctl is-active --quiet tradeviewchain.service; then
    echo "Service is running. Stopping and removing it."
    
    sudo systemctl stop tradeviewchain.service
    sudo rm -rf "$HOMEDIR"
    sudo rm -rf /etc/systemd/system/tradeviewchain.service
else
    echo "Service is not running. Skipping removal steps."
fi

# Path variables
CONFIG=$HOMEDIR/config/config.toml
APP_TOML=$HOMEDIR/config/app.toml
CLIENT=$HOMEDIR/config/client.toml
GENESIS=$HOMEDIR/config/genesis.json
TMP_GENESIS=$HOMEDIR/config/tmp_genesis.json

# validate dependencies are installed
command -v jq >/dev/null 2>&1 || {
	echo >&2 "jq not installed. More info: https://stedolan.github.io/jq/download/"
	exit 1
}

# used to exit on first error
set -e

# User prompt if an existing local node configuration is found.
if [ -d "$HOMEDIR" ]; then
	printf "\nAn existing folder at '%s' was found. You can choose to delete this folder and start a new local node with new keys from genesis. When declined, the existing local node is started. \n" "$HOMEDIR"
	echo "Overwrite the existing configuration and start a new local node? [y/n]"
	read -r overwrite
else
	overwrite="Y"
fi

# Setup local node if overwrite is set to Yes, otherwise skip setup
if [[ $overwrite == "y" || $overwrite == "Y" ]]; then
	# Remove the previous folder
	file_path="/etc/systemd/system/tradeviewchain.service"

# Check if the file exists
if [ -e "$file_path" ]; then
sudo systemctl stop tradeviewchain.service
echo "The file $file_path exists."
fi
	sudo rm -rf "$HOMEDIR"

	# Set client config
  tradeviewd config set client chain-id "$CHAINID" --home "$HOMEDIR"
	tradeviewd config set client keyring-backend "$KEYRING" --home "$HOMEDIR"
	
  echo "===========================Copy these keys with mnemonics and save it in safe place ==================================="
	tradeviewd keys add $KEYS --keyring-backend $KEYRING --algo $KEYALGO --home "$HOMEDIR"
	echo "========================================================================================================================"
	echo "========================================================================================================================"
	tradeviewd init $MONIKER -o --chain-id $CHAINID --home "$HOMEDIR"
  # Allocate genesis accounts (cosmos formatted addresses)
	tradeviewd add-genesis-account $KEYS 10000000000000000000000000000tvx --keyring-backend $KEYRING --home "$HOMEDIR"

	# Sign genesis transaction
	tradeviewd gentx ${KEYS} 1000000000000000000000000tvx --keyring-backend $KEYRING --chain-id $CHAINID --home "$HOMEDIR"
	
	# Collect genesis tx
	tradeviewd collect-gentxs --home "$HOMEDIR"
  
	# Change parameter token denominations to tvx
	jq '.app_state["staking"]["params"]["bond_denom"]="tvx"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
	jq '.app_state["crisis"]["constant_fee"]["denom"]="tvx"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
	jq '.app_state["gov"]["deposit_params"]["min_deposit"][0]["denom"]="tvx"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
	jq '.app_state["gov"]["params"]["min_deposit"][0]["denom"]="tvx"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
	# jq '.app_state["evm"]["params"]["evm_denom"]="tvx"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
  jq '.app_state["mint"]["params"]["mint_denom"]="tvx"' >"$TMP_GENESIS" "$GENESIS" && mv "$TMP_GENESIS" "$GENESIS"

	jq '.consensus_params["block"]["max_bytes"]="8388608"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    # jq '.app_state["mint"]["minter"]["inflation"]="0.080000000000000000"' >"$TMP_GENESIS" "$GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    # jq '.app_state["mint"]["params"]["inflation_rate_change"]="0.080000000000000000"' >"$TMP_GENESIS" "$GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    # jq '.app_state["mint"]["params"]["inflation_max"]="0.080000000000000000"' >"$TMP_GENESIS" "$GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    # jq '.app_state["mint"]["params"]["inflation_min"]="0.080000000000000000"' >"$TMP_GENESIS" "$GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
   # jq '.app_state["feemarket"]["params"]["base_fee"]="182855642857142"' >"$TMP_GENESIS" "$GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
	# Set gas limit in genesis
	jq '.consensus_params["block"]["max_gas"]="10000000"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
  jq '.consensus_params["block"]["max_bytes"]="5242880"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
  jq '.app_state["mint"]["params"]["blocks_per_year"]="5256000 "' >"$TMP_GENESIS" "$GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
  jq '.app_state["gov"]["deposit_params"]["max_deposit_period"]="1800s"' >"$TMP_GENESIS" "$GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
  jq '.app_state["gov"]["params"]["max_deposit_period"]="1800s"' >"$TMP_GENESIS" "$GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
  jq '.app_state["gov"]["voting_params"]["voting_period"]="1800s"' >"$TMP_GENESIS" "$GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
  jq '.app_state["gov"]["params"]["voting_period"]="1800s"' >"$TMP_GENESIS" "$GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
  jq '.app_state["staking"]["params"]["unbonding_time"]="1800s"' >"$TMP_GENESIS" "$GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
  jq '.app_state["slashing"]["params"]["downtime_jail_duration"]="600s"' >"$TMP_GENESIS" "$GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
  

  # Change proposal periods to pass within a reasonable time for local testing
	# sed -i.bak 's/"max_deposit_period": "172800s"/"max_deposit_period": "30s"/g' "$GENESIS"
	# sed -i.bak 's/"voting_period": "172800s"/"voting_period": "30s"/g' "$GENESIS"
	sed -i.bak 's/"expedited_voting_period": "86400s"/"expedited_voting_period": "600s"/g' "$GENESIS"

	#changes status in app,config files
    sed -i 's/timeout_commit = "3s"/timeout_commit = "6s"/g' "$CONFIG"
    #sed -i 's/pruning = "default"/pruning = "custom"/g' "$APP_TOML"
    sed -i 's/pruning-keep-recent = "0"/pruning-keep-recent = "100000"/g' "$APP_TOML"
    sed -i 's/pruning-interval = "0"/pruning-interval = "100"/g' "$APP_TOML"
    sed -i 's/seeds = ""/seeds = ""/g' "$CONFIG"
    sed -i 's/prometheus = false/prometheus = true/' "$CONFIG"
    sed -i 's/experimental_websocket_write_buffer_size = 200/experimental_websocket_write_buffer_size = 600/' "$CONFIG"
    sed -i 's/prometheus-retention-time  = "0"/prometheus-retention-time  = "1000000000000"/g' "$APP_TOML"
    sed -i 's/enabled = false/enabled = true/g' "$APP_TOML"
    sed -i 's/minimum-gas-prices = "0tvx"/minimum-gas-prices = "0.25tvx"/g' "$APP_TOML"
    sed -i 's/enable = false/enable = true/g' "$APP_TOML"
    sed -i 's/swagger = false/swagger = true/g' "$APP_TOML"
    sed -i 's/enabled-unsafe-cors = false/enabled-unsafe-cors = true/g' "$APP_TOML"
    sed -i 's/enable-unsafe-cors = false/enable-unsafe-cors = true/g' "$APP_TOML"
    sed -i '/\[rosetta\]/,/^\[.*\]/ s/enable = true/enable = false/' "$APP_TOML"
    sed -i 's/localhost/0.0.0.0/g' "$APP_TOML"
    sed -i 's/localhost/0.0.0.0/g' "$CONFIG"
    sed -i 's/:26660/0.0.0.0:26660/g' "$CONFIG"
    sed -i 's/localhost/0.0.0.0/g' "$CLIENT"
    sed -i 's/127.0.0.1/0.0.0.0/g' "$APP_TOML"
    sed -i 's/127.0.0.1/0.0.0.0/g' "$CONFIG"
    sed -i 's/127.0.0.1/0.0.0.0/g' "$CLIENT"
    sed -i 's/\[\]/["*"]/g' "$CONFIG"
	  sed -i 's/\["\*",\]/["*"]/g' "$CONFIG"
  
# sed -i 's/enable = false/enable = true/g' "$CONFIG"
# sed -i 's/rpc_servers \s*=\s* ""/rpc_servers = ""/g' "$CONFIG"
# sed -i 's/trust_hash \s*=\s* ""/trust_hash = "8223EF205275D355369D43391DA33A7AD7355932B50E50A7C092A0729084C739"/g' "$CONFIG"
# sed -i 's/trust_height = 0/trust_height = 5063000/g' "$CONFIG"
# sed -i 's/trust_period = "112h0m0s"/trust_period = "168h0m0s"/g' "$CONFIG"
# sed -i 's/flush_throttle_timeout = "100ms"/flush_throttle_timeout = "10ms"/g' "$CONFIG"
# sed -i 's/peer_gossip_sleep_duration = "100ms"/peer_gossip_sleep_duration = "10ms"/g' "$CONFIG"

	# these are some of the node ids help to sync the node with p2p connections
	 sed -i 's/persistent_peers \s*=\s* ""/persistent_peers = "87e07425a67ac29268ee8f4e9ec370a8cdd1f4a9@44.235.160.53,"/g' "$CONFIG"

	# remove the genesis file from binary
	 rm -rf $HOMEDIR/config/genesis.json

	# paste the genesis file
	 cp $current_path/genesis.json $HOMEDIR/config

	# Run this to ensure everything worked and that the genesis file is setup correctly
	tradeviewd validate-genesis --home "$HOMEDIR"

  # Don't enable memiavl by default
	grep -q -F '[memiavl]' "$APP_TOML" && sed -i '/\[memiavl\]/,/^\[/ s/enable = true/enable = false/' "$APP_TOML"
  # Don't enable Rosetta API by default
	grep -q -F '[rosetta]' "$APP_TOML" && sed -i '/\[rosetta\]/,/^\[/ s/enable = true/enable = false/' "$APP_TOML"
	# Don't enable versionDB by default
	grep -q -F '[versiondb]' "$APP_TOML" && sed -i '/\[versiondb\]/,/^\[/ s/enable = true/enable = false/' "$APP_TOML"
	
	echo "export DAEMON_NAME=tradeviewd" >> ~/.profile
    echo "export DAEMON_HOME="$HOMEDIR"" >> ~/.profile
    source ~/.profile
    echo $DAEMON_HOME
    echo $DAEMON_NAME

	cosmovisor init "${INSTALL_PATH}${BINARY}"

	
	TENDERMINTPUBKEY=$(tradeviewd tendermint show-validator --home $HOMEDIR | grep "key" | cut -c12-)
	NodeId=$(tradeviewd tendermint show-node-id --home $HOMEDIR --keyring-backend $KEYRING)
	BECH32ADDRESS=$(tradeviewd keys show ${KEYS} --home $HOMEDIR --keyring-backend $KEYRING| grep "address" | cut -c12-)

	echo "========================================================================================================================"
	echo "tendermint Key==== "$TENDERMINTPUBKEY
	echo "BECH32Address==== "$BECH32ADDRESS
	echo "NodeId ===" $NodeId
	echo "========================================================================================================================"

fi

#========================================================================================================================================================
sudo su -c  "echo '[Unit]
Description=tradeview Node
Wants=network-online.target
After=network-online.target
[Service]
User=$(whoami)
Group=$(whoami)
Type=simple
ExecStart=$COSMOVISOR_PATH run start --home $DAEMON_HOME --chain-id "$CHAINID" 
Restart=always
RestartSec=3
LimitNOFILE=4096
Environment="DAEMON_NAME=tradeviewd"
Environment="DAEMON_HOME="$HOMEDIR""
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="DAEMON_LOG_BUFFER_SIZE=512"
Environment="UNSAFE_SKIP_BACKUP=false"
[Install]
WantedBy=multi-user.target'> /etc/systemd/system/tradeviewchain.service"

sudo systemctl daemon-reload
sudo systemctl enable tradeviewchain.service
# tradeviewd tendermint unsafe-reset-all --home $HOMEDIR
# sudo systemctl start tradeviewchain.service
