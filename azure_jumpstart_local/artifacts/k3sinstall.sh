#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

# Function to get credentials
get_credentials() {
    echo "Welcome to K3s Installation!"
    echo "Please enter your Azure credentials:"
    read -p "App ID: " APP_ID
    read -sp "Client Secret: " CLIENT_SECRET
    echo  # New line after hidden input
    read -p "Tenant ID: " TENANT_ID
}

# Clear the screen and get credentials
clear
get_credentials

# Update and install required dependencies
echo "Updating system and installing dependencies..."
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y curl wget apt-transport-https jq

# Install Azure CLI
echo "Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Azure login
echo "Logging into Azure..."
az login --service-principal --username "$APP_ID" --password "$CLIENT_SECRET" --tenant "$TENANT_ID"


# Download and install K3s
echo "Downloading and installing K3s..."
curl -sfL https://get.k3s.io | sudo sh -

# Enable and start K3s service
echo "Enabling and starting K3s service..."
sudo systemctl enable k3s
sudo systemctl start k3s

# Configure kubectl to use K3s
echo "Setting up kubectl access..."
mkdir -p $HOME/.kube
sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=$HOME/.kube/config

# Install connected Kubernetes extension
echo "Installing connected Kubernetes extension..."
az extension add --name connectedk8s

# Register required providers
echo "Registering Azure providers..."
az provider register --namespace Microsoft.Kubernetes
az provider register --namespace Microsoft.KubernetesConfiguration
az provider register --namespace Microsoft.ExtendedLocation

# Connect K3s cluster to Azure Arc
echo "Connecting K3s cluster to Azure Arc..."
az connectedk8s connect --name azlocal-arc --resource-group azlocal-lakshit

echo "K3s and Azure Arc installation completed successfully!"
kubectl get nodes

# Disable the service after successful completion
echo "Disabling the installation service..."
sudo systemctl disable k3sinstall.service

echo "Installation complete! The system will no longer run this script on boot."
