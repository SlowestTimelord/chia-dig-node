#!/bin/bash

# Variables
USER_NAME=${SUDO_USER:-$(whoami)}  # Use SUDO_USER if available, otherwise fall back to whoami
SERVICE_NAME="dig@$USER_NAME.service"
SERVICE_FILE_PATH="/etc/systemd/system/$SERVICE_NAME"
WORKING_DIR=$(pwd)

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if Docker is installed
if ! command_exists docker; then
  echo "Error: Docker is not installed."
  echo "Please install Docker before running this script. Visit https://docs.docker.com/get-docker/ for installation instructions."
  exit 1
fi

# Check if Docker Compose is installed
if ! command_exists docker-compose; then
  echo "Error: Docker Compose is not installed."
  echo "Please install Docker Compose before running this script. Visit https://docs.docker.com/compose/install/ for installation instructions."
  exit 1
fi

# Check if the script is being run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Add the current user to the Docker group
echo "Adding $USER_NAME to the docker group..."
usermod -aG docker "$USER_NAME"

# Check if the working directory exists
if [ ! -d "$WORKING_DIR" ]; then
  echo "Working directory $WORKING_DIR does not exist. Please create it first."
  exit 1
fi

# Prompt user for values, but generate DIG_USERNAME and DIG_PASSWORD automatically
echo "Generating high-entropy DIG_USERNAME and DIG_PASSWORD..."
DIG_USERNAME=$(openssl rand -hex 16)
DIG_PASSWORD=$(openssl rand -hex 32)

# Ask user for TRUSTED_FULLNODE and default to "not-provided" if left blank
read -p "Please enter the TRUSTED_FULLNODE (your personal full node's public IP for better performance) [optional]: " TRUSTED_FULLNODE
TRUSTED_FULLNODE=${TRUSTED_FULLNODE:-"not-provided"}

# Ask user for PUBLIC_IP and default to "not-provided" if left blank
read -p "If needed, enter a PUBLIC_IP override (leave blank for auto-detection): " PUBLIC_IP
PUBLIC_IP=${PUBLIC_IP:-"not-provided"}

# Echo the variables back to the user
echo "DIG_USERNAME: $DIG_USERNAME"
echo "DIG_PASSWORD: $DIG_PASSWORD"
echo "TRUSTED_FULLNODE: $TRUSTED_FULLNODE"
echo "PUBLIC_IP: $PUBLIC_IP"
echo "These values will be used in the DIG CLI."

# Explanation of the TRUSTED_FULLNODE and PUBLIC_IP
echo "TRUSTED_FULLNODE is optional. It should be your own full node's public IP if applicable. Using your own node can provide better performance."
echo "PUBLIC_IP should only be set if your network setup requires an IP override (e.g., behind BGP). Otherwise, leave it blank and the public IP will be auto-detected."

# Create docker-compose.yml with the provided values
DOCKER_COMPOSE_FILE=./docker-compose.yml
cat <<EOF > $DOCKER_COMPOSE_FILE
version: '3.8'
services:
  propagation-server:
    image: dignetwork/dig-propagation-server:latest-alpha
    ports:
      - "4159:4159"
    volumes:
      - ~/.dig/remote:/.dig
    environment:
      - DIG_USERNAME=$DIG_USERNAME
      - DIG_PASSWORD=$DIG_PASSWORD
      - DIG_FOLDER_PATH=/.dig
      - PORT=4159
      - REMOTE_NODE=1
      - TRUSTED_FULLNODE=$TRUSTED_FULLNODE
    restart: always

  content-server:
    image: dignetwork/dig-content-server:latest-alpha
    ports:
      - "80:80"
    volumes:
      - ~/.dig/remote:/.dig
    environment:
      - DIG_FOLDER_PATH=/.dig
      - PORT=80
      - REMOTE_NODE=1
      - TRUSTED_FULLNODE=$TRUSTED_FULLNODE
    restart: always

  incentive-server:
    image: dignetwork/dig-incentive-server:latest-alpha
    ports:
      - "4160:4160"
    volumes:
      - ~/.dig/remote:/.dig
    environment:
      - DIG_USERNAME=$DIG_USERNAME
      - DIG_PASSWORD=$DIG_PASSWORD
      - DIG_FOLDER_PATH=/.dig
      - PORT=4160
      - REMOTE_NODE=1
      - TRUSTED_FULLNODE=$TRUSTED_FULLNODE
      - PUBLIC_IP=$PUBLIC_IP
    restart: always

networks:
  default:
    name: dig_network
EOF

echo "docker-compose.yml file created successfully at $DOCKER_COMPOSE_FILE."

# Create the systemd service file
echo "Creating systemd service file at $SERVICE_FILE_PATH..."

cat <<EOF > $SERVICE_FILE_PATH
[Unit]
Description=Dig Node Docker Compose
Documentation=https://dig.net
After=network.target docker.service
Requires=docker.service

[Service]
WorkingDirectory=$WORKING_DIR
ExecStart=/usr/local/bin/docker-compose up
ExecStop=/usr/local/bin/docker-compose down
Restart=always

User=$USER_NAME
Group=docker

# Time to wait before forcefully stopping the container
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd to recognize the new service
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Enable the service to start on boot
echo "Enabling $SERVICE_NAME service..."
systemctl enable "dig@$USER_NAME.service"

# Start the service
echo "Starting $SERVICE_NAME service..."
systemctl start "dig@$USER_NAME.service"

# Check the status of the service
echo "Checking the status of the service..."
systemctl status "dig@$USER_NAME.service"

echo "Service $SERVICE_NAME installed and activated successfully."

echo "Please log out and log back in for the Docker group changes to take effect."
