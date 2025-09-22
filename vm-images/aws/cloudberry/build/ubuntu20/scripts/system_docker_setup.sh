#!/bin/bash
set -e

# Update package index
sudo apt-get update

# Install prerequisites
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Set up the stable Docker repository
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index (again)
sudo apt-get update

# Install Docker
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# Configure Docker daemon
echo '{"default-shm-size": "1G"}' | sudo tee /etc/docker/daemon.json

# Start and enable Docker service
sudo systemctl start docker
sudo systemctl status docker
sudo systemctl enable docker

# Add current user and cbadmin to the docker group
sudo usermod -aG docker $(whoami)
sudo usermod -aG docker cbadmin

# Install unzip and AWS CLI v2
sudo apt-get install -y unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
rm -f awscliv2.zip

# Clean up
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
