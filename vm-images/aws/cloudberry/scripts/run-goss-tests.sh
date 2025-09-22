#!/bin/bash

# Goss-based AMI Testing Script for Cloudberry Database Build Environment
# This script replaces the previous Testinfra-based testing with Goss

set -euo pipefail

# Usage function
usage() {
  echo "Usage: $0 -a <ami-id> [-r <region>] [-k <key-name>] [-s <instance-size>] [-n]"
  echo ""
  echo "  -a <ami-id>           AMI ID to test (required)"
  echo "  -r <region>           AWS region (default: us-west-2)"
  echo "  -k <key-name>         SSH key pair name (if not specified, a temporary key will be created)"
  echo "  -s <instance-size>    EC2 instance type (default: t3.medium)"
  echo "  -n                    No cleanup - leave resources running after test"
}

# Check for required commands
for cmd in aws curl nc goss; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "$cmd could not be found. Please install $cmd to proceed."
    case "$cmd" in
        goss) echo "Install with: curl -L https://github.com/goss-org/goss/releases/latest/download/goss-linux-amd64 -o /usr/local/bin/goss && chmod +x /usr/local/bin/goss" ;;
        aws) echo "Install with: pip install awscli or download from AWS" ;;
        curl) echo "Install with: sudo dnf install curl" ;;
        nc) echo "Install with: sudo dnf install nmap-ncat" ;;
    esac
    exit 1
  fi
done

# Default values
REGION="us-west-2"
INSTANCE_SIZE="t3.medium"
NO_CLEANUP=false
KEY_NAME=""
CREATE_TEMP_KEY=false

# Parse command-line arguments
while getopts "a:r:k:s:nh" opt; do
  case $opt in
    a) AMI_ID="$OPTARG" ;;
    r) REGION="$OPTARG" ;;
    k) KEY_NAME="$OPTARG" ;;
    s) INSTANCE_SIZE="$OPTARG" ;;
    n) NO_CLEANUP=true ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

# Validate required arguments
if [[ -z "${AMI_ID:-}" ]]; then
  echo "Error: AMI ID is required."
  usage
  exit 1
fi

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." &> /dev/null && pwd)"
GOSS_FILE="${PROJECT_ROOT}/build/rocky9/tests/goss.yaml"

# Check if Goss test file exists
if [[ ! -f "$GOSS_FILE" ]]; then
  echo "Error: Goss test file not found at $GOSS_FILE"
  exit 1
fi

echo "==================================="
echo "Cloudberry AMI Goss Testing"
echo "==================================="
echo "AMI ID: $AMI_ID"
echo "Region: $REGION" 
echo "Instance Type: $INSTANCE_SIZE"
echo "Goss Tests: $GOSS_FILE"
echo "==================================="

# Generate timestamp for unique resource naming
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# Handle SSH key creation
if [[ -z "$KEY_NAME" ]]; then
  CREATE_TEMP_KEY=true
  KEY_NAME="key-goss-test-${TIMESTAMP}"
fi

PRIVATE_KEY_FILE="${PROJECT_ROOT}/build/rocky9/${KEY_NAME}.pem"
SECURITY_GROUP_NAME="goss-test-sg-${TIMESTAMP}"
SECURITY_GROUP_ID=""
INSTANCE_ID=""
HOSTNAME=""

# Variables for cleanup tracking
CLEANED_UP=false

# Cleanup function
cleanup() {
  if [ "$CLEANED_UP" = true ] || [ "$NO_CLEANUP" = true ]; then
    return
  fi
  
  echo "Cleaning up resources..."
  
  # Terminate instance
  if [[ -n "${INSTANCE_ID}" ]]; then
    echo "Terminating EC2 instance ${INSTANCE_ID}..."
    aws ec2 terminate-instances --instance-ids ${INSTANCE_ID} --region ${REGION} >/dev/null 2>&1 || true
    echo "Waiting for instance to terminate..."
    aws ec2 wait instance-terminated --instance-ids ${INSTANCE_ID} --region ${REGION} || true
    echo "Instance terminated."
  fi
  
  # Delete security group
  if [[ -n "${SECURITY_GROUP_ID}" ]]; then
    echo "Deleting security group ${SECURITY_GROUP_ID}..."
    aws ec2 delete-security-group --group-id ${SECURITY_GROUP_ID} --region ${REGION} >/dev/null 2>&1 || true
  fi
  
  # Delete temporary key pair and file
  if [ "$CREATE_TEMP_KEY" = true ]; then
    if [[ -f "${PRIVATE_KEY_FILE}" ]]; then
      echo "Removing temporary key file ${PRIVATE_KEY_FILE}..."
      rm -f "${PRIVATE_KEY_FILE}"
    fi
    
    echo "Deleting temporary key pair ${KEY_NAME}..."
    aws ec2 delete-key-pair --key-name ${KEY_NAME} --region ${REGION} >/dev/null 2>&1 || true
  fi
  
  CLEANED_UP=true
  echo "Cleanup completed."
}

# Set up error handling
trap cleanup EXIT
trap cleanup ERR

# Create temporary SSH key if needed
if [ "$CREATE_TEMP_KEY" = true ]; then
  echo "Creating temporary SSH key pair..."
  aws ec2 create-key-pair --key-name ${KEY_NAME} --query 'KeyMaterial' --output text --region ${REGION} > ${PRIVATE_KEY_FILE}
  chmod 400 ${PRIVATE_KEY_FILE}
  echo "Created temporary key pair: ${KEY_NAME}"
fi

# Get local IP for security group
echo "Getting local IP address for security group..."
LOCAL_IP=$(curl -s http://checkip.amazonaws.com)/32
echo "Local IP: ${LOCAL_IP}"

# Create security group
echo "Creating security group..."
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
  --group-name "${SECURITY_GROUP_NAME}" \
  --description "Temporary security group for Goss testing AMI ${AMI_ID}" \
  --region ${REGION} \
  --query 'GroupId' \
  --output text)

echo "Created security group: ${SECURITY_GROUP_ID}"

# Add SSH rule to security group
echo "Adding SSH access rule..."
aws ec2 authorize-security-group-ingress \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol tcp \
  --port 22 \
  --cidr ${LOCAL_IP} \
  --region ${REGION}

# Launch EC2 instance
echo "Launching EC2 instance with AMI ${AMI_ID}..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id ${AMI_ID} \
  --instance-type ${INSTANCE_SIZE} \
  --key-name ${KEY_NAME} \
  --security-group-ids ${SECURITY_GROUP_ID} \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=goss-test-${TIMESTAMP}},{Key=Purpose,Value=AMI-Testing}]" \
  --region ${REGION} \
  --query "Instances[0].InstanceId" \
  --output text)

echo "Launched instance: ${INSTANCE_ID}"

# Wait for instance to be running
echo "Waiting for instance to be in running state..."
aws ec2 wait instance-running --instance-ids ${INSTANCE_ID} --region ${REGION}

# Get instance hostname
HOSTNAME=$(aws ec2 describe-instances \
  --instance-ids ${INSTANCE_ID} \
  --query "Reservations[*].Instances[*].PublicDnsName" \
  --output text \
  --region ${REGION})

echo "Instance is running. Public DNS: ${HOSTNAME}"

# Wait for SSH to become available
echo "Waiting for SSH to become available..."
for ((i=1; i<=30; i++)); do
  if nc -zv ${HOSTNAME} 22 >/dev/null 2>&1; then
    echo "SSH is available on ${HOSTNAME}"
    break
  else
    echo "SSH not available yet. Attempt $i/30..."
    sleep $((i*2))
  fi
  
  if [ $i -eq 30 ]; then
    echo "ERROR: SSH did not become available after 30 attempts"
    exit 1
  fi
done

# Copy Goss test file to the instance
echo "Copying Goss test configuration to instance..."
scp -i ${PRIVATE_KEY_FILE} \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    "${GOSS_FILE}" \
    rocky@${HOSTNAME}:~/goss.yaml

# Run Goss tests
echo ""
echo "==================================="
echo "Running Goss Tests"
echo "==================================="

# Execute Goss tests on the remote instance
ssh -i ${PRIVATE_KEY_FILE} \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    rocky@${HOSTNAME} \
    'sudo goss --gossfile ~/goss.yaml validate --format junit > ~/goss-results.xml 2>/dev/null; sudo goss --gossfile ~/goss.yaml validate --format pretty'

# Copy test results back
echo ""
echo "==================================="
echo "Retrieving Test Results"
echo "==================================="

scp -i ${PRIVATE_KEY_FILE} \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    rocky@${HOSTNAME}:~/goss-results.xml \
    "${PROJECT_ROOT}/build/rocky9/goss-test-results-${TIMESTAMP}.xml" || true

echo ""
echo "==================================="
echo "Test Summary"
echo "==================================="
echo "✅ Goss tests completed successfully!"
echo "📄 JUnit results saved to: goss-test-results-${TIMESTAMP}.xml"
echo "🖥️  Instance: ${INSTANCE_ID} (${HOSTNAME})"
echo "🔧 AMI: ${AMI_ID}"

if [ "$NO_CLEANUP" = true ]; then
  echo ""
  echo "⚠️  Resources left running (--no-cleanup specified):"
  echo "   Instance: ${INSTANCE_ID}"
  echo "   Security Group: ${SECURITY_GROUP_ID}"
  echo "   SSH Key: ${KEY_NAME}"
  echo ""
  echo "   To connect: ssh -i ${PRIVATE_KEY_FILE} rocky@${HOSTNAME}"
  echo "   Remember to clean up manually when done!"
fi

echo "==================================="