#!/usr/bin/env bash
set -euo pipefail

LOCATION="belgiumcentral"
RESOURCE_GROUP="rg-ejercicio-cli-belgiumcentral"
VNET_NAME="vnet-ejercicio-cli-belgiumcentral"
SUBNET_NAME="snet-default"
NSG_NAME="nsg-ejercicio-cli"
PUBLIC_IP_NAME="pip-vm-cli-01"
NIC_NAME="nic-vm-cli-01"
VM_NAME="vm-linux-cli-01"
SSH_SOURCE="${SSH_SOURCE:-*}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SSH_DIR="$PROJECT_ROOT/.ssh"
SSH_PRIVATE_KEY="$SSH_DIR/vm-cli-key"
SSH_PUBLIC_KEY="$SSH_PRIVATE_KEY.pub"

if [[ -f "$SSH_PRIVATE_KEY" && -f "$SSH_PUBLIC_KEY" ]]; then
  echo "Using existing SSH key pair: $SSH_PRIVATE_KEY"
elif [[ ! -e "$SSH_PRIVATE_KEY" && ! -e "$SSH_PUBLIC_KEY" ]]; then
  mkdir -p "$SSH_DIR"
  ssh-keygen -t rsa -b 4096 -f "$SSH_PRIVATE_KEY" -N ""
else
  echo "SSH key pair is incomplete. Check $SSH_PRIVATE_KEY and $SSH_PUBLIC_KEY." >&2
  exit 1
fi

echo "WARNING: the SSH rule allows connections from '$SSH_SOURCE'."
echo "Set SSH_SOURCE to a trusted IP/CIDR before running this script when possible."

# 1. Create the resource group.
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --tags environment=development project=practica-2 created-by=cli

# 2. Create the virtual network.
az network vnet create \
  --name "$VNET_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --address-prefix 10.1.0.0/16

# 3. Create the subnet.
az network vnet subnet create \
  --name "$SUBNET_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --address-prefix 10.1.0.0/24

# 4. Create the network security group.
az network nsg create \
  --name "$NSG_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION"

# 5. Allow SSH through the network security group.
az network nsg rule create \
  --name AllowSSH \
  --nsg-name "$NSG_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --priority 300 \
  --source-address-prefixes "$SSH_SOURCE" \
  --destination-port-ranges 22 \
  --access Allow \
  --protocol Tcp

# 6. Create a static public IP address.
az network public-ip create \
  --name "$PUBLIC_IP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard \
  --allocation-method Static

# 7. Create the network interface.
az network nic create \
  --name "$NIC_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --vnet-name "$VNET_NAME" \
  --subnet "$SUBNET_NAME" \
  --network-security-group "$NSG_NAME" \
  --public-ip-address "$PUBLIC_IP_NAME"

# 8. Create the VM. D2as_v4 was used after B1s was unavailable in the region.
az vm create \
  --name "$VM_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --size Standard_D2as_v4 \
  --image Ubuntu2204 \
  --nics "$NIC_NAME" \
  --admin-username azureuser \
  --ssh-key-values "$SSH_PUBLIC_KEY" \
  --tags environment=development project=master-cloud

# 9. Get the public IP address.
# Query Azure so the script still prints the correct value if it changes.
PUBLIC_IP="$(az network public-ip show \
  --name "$PUBLIC_IP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query ipAddress \
  --output tsv)"
printf 'VM public IP: %s\n' "$PUBLIC_IP"

# 10. List the resources created in the resource group.
az resource list \
  --resource-group "$RESOURCE_GROUP" \
  --output table

# 11. Show the VM details.
az vm show \
  --name "$VM_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --output json

printf '\nTo connect to the VM, run:\nssh -i "%s" azureuser@%s\n' "$SSH_PRIVATE_KEY" "$PUBLIC_IP"
