#!/bin/bash
#
# Script Name: packer-build-and-test.sh
#
# Description:
# This script automates the process of validating, building, testing, and
# publishing an Amazon Machine Image (AMI) using Packer. It also handles
# the creation and cleanup of associated AWS resources like EC2 instances,
# key pairs, and security groups.
#
# Usage:
# ./packer-build-and-test.sh
#
# Prerequisites:
# - AWS CLI configured with appropriate credentials
# - Packer installed
# - jq, pytest, nc, and curl installed
# - The script assumes the presence of a Packer HCL file (main.pkr.hcl) in
#   the current directory.
#
# Notes:
# - Ensure you have the necessary IAM permissions to create and manage EC2
#   instances, AMIs, and security groups.
# - The script cleans up resources upon completion or failure to avoid
#   unnecessary costs.

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing packer-build-and-test.sh..."

# Function to check if a command is available in the system
# Arguments:
#   $1 - Name of the command to check
command_exists() {
  command -v "$1" &> /dev/null
}

# Check for required commands
## for cmd in pytest packer aws jq nc curl; do
for cmd in packer aws jq nc curl; do
  if ! command_exists "$cmd"; then
    echo "$cmd could not be found. Please install $cmd to proceed."
    case "$cmd" in
        pytest) echo "Install with: pip install pytest" ;;
        packer) echo "Install with: Download from https://www.packer.io/downloads" ;;
        aws) echo "Install with: pip install awscli" ;;
        jq) echo "Install with: sudo apt-get install jq" ;;
        nc) echo "Install with: sudo apt-get install netcat" ;;
        curl) echo "Install with: sudo apt-get install curl" ;;
    esac
    exit 1
  fi
done

# Get the directory of this script and the current working directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
CURRENT_DIR="$(pwd)"

# Define the path to the Packer HCL file
HCL_FILE="${CURRENT_DIR}/main.pkr.hcl"

# Check if the HCL file exists
if [ ! -f "$HCL_FILE" ]; then
  echo "Error: Packer HCL file not found at ${HCL_FILE}. Aborting."
  exit 1
fi

# Derive OS_NAME and VM_TYPE from the HCL file's location
VM_TYPE=$(basename "$(dirname "$CURRENT_DIR")")  # VM_TYPE is the parent directory name
OS_NAME=$(basename "$CURRENT_DIR")  # OS_NAME is the current directory name
# Determine the correct SSH user based on the OS
case "$OS_NAME" in
    rocky*|centos*|rhel*)
        OS_USER="rocky"
        ;;
    ubuntu*)
        OS_USER="ubuntu"
        ;;
    amazon*|amzn*)
        OS_USER="ec2-user"
        ;;
    *)
        OS_USER="rocky"  # Default to rocky for cloudberry builds
        ;;
esac

echo "Using SSH user: ${OS_USER} for OS: ${OS_NAME}"

# Define AWS region and timestamp for unique naming
REGION="${AWS_REGION:-us-west-2}"   # AWS region where the AMI will be created and tested
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")  # Timestamp for unique resource naming

# Variables for AWS resources
export PKR_VAR_KEY_NAME="key-${VM_TYPE}-${OS_NAME}-${TIMESTAMP}"  # Name for the temporary key pair
export PKR_VAR_PRIVATE_KEY_FILE="${CURRENT_DIR}/${PKR_VAR_KEY_NAME}.pem"  # Path to the generated private key file
SECURITY_GROUP_NAME="${VM_TYPE}-${OS_NAME}-${TIMESTAMP}-sg"  # Name for the temporary security group
SECURITY_GROUP_ID=""
INSTANCE_ID=""
AMI_ID=""
HOSTNAME=""
AMI_NAME=""
CLEANED_UP=false
BLOCK_PUBLIC_ACCESS_WAS_ENABLED=false

# Variable to track successful execution
SUCCESS=false

# Function to rename the AMI based on the test result
# Arguments:
#   $1 - Result of the test (e.g., "PASSED", "FAILED")
rename_ami() {
  local result=$1
  if [ -n "${AMI_ID}" ]; then
    NEW_NAME="${AMI_NAME}-${result}"
    echo "Renaming AMI to indicate ${result}: ${NEW_NAME}"
    # Update the tag of the AMI
    aws ec2 create-tags --resources ${AMI_ID} --tags Key=Name,Value=${NEW_NAME} --region ${REGION}
  fi
}

# Function to check if block public access for AMIs is enabled
check_block_public_access() {
  echo "Checking if block public access for AMIs is enabled..."
  BLOCK_PUBLIC_ACCESS_STATE=$(aws ec2 get-image-block-public-access-state --region ${REGION} --query 'ImageBlockPublicAccessState' --output text)
  if [ "$BLOCK_PUBLIC_ACCESS_STATE" == "block-new-sharing" ]; then
    echo "Block public access for AMIs is enabled."
    BLOCK_PUBLIC_ACCESS_WAS_ENABLED=true
  else
    echo "Block public access for AMIs is not enabled."
    BLOCK_PUBLIC_ACCESS_WAS_ENABLED=false
  fi
}

# Function to disable block public access for AMIs if it was previously enabled
disable_image_block_public_access() {
  if [ "$BLOCK_PUBLIC_ACCESS_WAS_ENABLED" == "true" ]; then
    echo "Disabling block public access for AMIs..."
    aws ec2 disable-image-block-public-access --region ${REGION}
    echo "Block public access for AMIs disabled."
  fi
}

# Function to re-enable block public access for AMIs if it was originally enabled
enable_image_block_public_access() {
  if [ "$BLOCK_PUBLIC_ACCESS_WAS_ENABLED" == "true" ]; then
    echo "Re-enabling block public access for AMIs..."
    aws ec2 enable-image-block-public-access --region ${REGION} --image-block-public-access-state block-new-sharing
    echo "Block public access for AMIs re-enabled."
  fi
}

# Function to make the AMI public
make_ami_public() {
  if [ -n "${AMI_ID}" ]; then
    echo "Making AMI public: ${AMI_ID}"
    aws ec2 modify-image-attribute --image-id ${AMI_ID} --launch-permission "Add=[{Group=all}]" --region ${REGION}
  fi
}

# Function to verify the AMI launch permissions
verify_launch_permissions() {
  if [ -n "${AMI_ID}" ]; then
    echo "Verifying launch permissions for AMI: ${AMI_ID}"
    aws ec2 describe-image-attribute --image-id ${AMI_ID} --attribute launchPermission --region ${REGION}
  fi
}

# Function to clean up resources
cleanup() {
  if [ "$CLEANED_UP" = true ]; then
    return
  fi
  echo "Cleaning up..."
  if [ -n "${INSTANCE_ID}" ]; then
    echo "Terminating the EC2 instance..."
    aws ec2 terminate-instances --instance-ids ${INSTANCE_ID} --region ${REGION}
    aws ec2 wait instance-terminated --instance-ids ${INSTANCE_ID} --region ${REGION}
    echo "EC2 instance ${INSTANCE_ID} terminated successfully."
  fi
  if [ -f "${PKR_VAR_PRIVATE_KEY_FILE}" ]; then
    echo "Removing key file ${PKR_VAR_PRIVATE_KEY_FILE}"
    rm -f ${PKR_VAR_PRIVATE_KEY_FILE}
  fi
  if aws ec2 describe-key-pairs --key-name ${PKR_VAR_KEY_NAME} --region ${REGION} > /dev/null 2>&1; then
    echo "Deleting key pair ${PKR_VAR_KEY_NAME}"
    aws ec2 delete-key-pair --key-name ${PKR_VAR_KEY_NAME} --region ${REGION} || true
  fi
  if [ -n "${SECURITY_GROUP_ID}" ]; then
    echo "Deleting security group ${SECURITY_GROUP_ID}"
    aws ec2 delete-security-group --group-id ${SECURITY_GROUP_ID} --region ${REGION} || true
  fi
  CLEANED_UP=true
  echo "Cleanup completed."

  # Print final success message if everything was successful
  if [ "$SUCCESS" = true ]; then
    echo "-----------------------------------"
    echo "AMI Build and Test Completed"
    echo "-----------------------------------"
    echo "AMI ID: ${AMI_ID}"
    echo "AMI Name: ${AMI_NAME}"
    echo "Region: ${REGION}"
    echo "This AMI has passed all tests and is now public."
    echo "-----------------------------------"
  fi
}

# Error handler to rename the AMI as "FAILED" and perform cleanup
error_handler() {
  echo "An error occurred. Running cleanup and renaming AMI if necessary."
  rename_ami "FAILED"
  cleanup
  exit 1
}

# Trap errors and EXIT signals to ensure cleanup is performed
trap cleanup EXIT
trap error_handler ERR

# Step 1: Create a new key pair for SSH access
echo "Creating new key pair..."
aws ec2 create-key-pair --key-name ${PKR_VAR_KEY_NAME} --query 'KeyMaterial' --output text --region ${REGION} > ${PKR_VAR_PRIVATE_KEY_FILE}
chmod 400 ${PKR_VAR_PRIVATE_KEY_FILE}
echo "Created key pair ${PKR_VAR_KEY_NAME} and saved to ${PKR_VAR_PRIVATE_KEY_FILE}"

# Step 2: Validate the Packer template
echo "Validating Packer template..."
if ! packer validate -var "vm_type=${VM_TYPE}" -var "os_name=${OS_NAME}" "${HCL_FILE}"; then
  echo "Packer template validation failed. Aborting."
  exit 1
fi

# Step 3: Build the AMI using the Packer template
echo "Building the Packer template..."
packer build \
       -var vm_type=${VM_TYPE} \
       -var os_name=${OS_NAME} \
       "${HCL_FILE}"

# Step 4: Parse the AMI ID from the Packer manifest file
echo "Parsing the AMI ID from packer-manifest.json..."
AMI_ID=$(jq -r '.builds[-1].artifact_id' packer-manifest.json | cut -d':' -f2)

# Step 5: Retrieve the AMI name
AMI_NAME=$(aws ec2 describe-images --image-ids ${AMI_ID} --query "Images[*].Name" --output text --region ${REGION})

# Step 6: Retrieve local IP address to restrict SSH access to the current machine
LOCAL_IP=$(curl -s http://checkip.amazonaws.com)/32

# Step 7: Create a new security group to allow SSH access
echo "Creating new security group..."
SECURITY_GROUP_ID=$(aws ec2 create-security-group --group-name "${SECURITY_GROUP_NAME}" --description "Security group for ${OS_NAME} ${VM_TYPE}" --region ${REGION} --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id ${SECURITY_GROUP_ID} --protocol tcp --port 22 --cidr ${LOCAL_IP} --region ${REGION}
echo "Created security group ${SECURITY_GROUP_ID} with SSH access for IP ${LOCAL_IP}"

# Step 8: Start a new EC2 instance using the created AMI
echo "Starting a new EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances --image-id ${AMI_ID} --instance-type t3.medium --key-name ${PKR_VAR_KEY_NAME} --security-group-ids ${SECURITY_GROUP_ID} --query "Instances[0].InstanceId" --output text --region ${REGION})

# Step 9: Wait until the instance is in the running state
echo "Waiting for the instance to be in running state..."
aws ec2 wait instance-running --instance-ids ${INSTANCE_ID} --region ${REGION}

# Step 10: Retrieve the public DNS name of the instance
HOSTNAME=$(aws ec2 describe-instances --instance-ids ${INSTANCE_ID} --query "Reservations[*].Instances[*].PublicDnsName" --output text --region ${REGION})

# Step 11: Loop until SSH access is available on the instance
echo "Waiting for SSH to become available on ${HOSTNAME}..."
for ((i=1; i<=30; i++)); do
  if nc -zv ${HOSTNAME} 22 2>&1 | grep -q 'succeeded'; then
    echo "SSH is available on ${HOSTNAME}"
    break
  else
    echo "SSH is not available yet. Retry $i/30..."
    sleep $((i*2))
  fi

  if [ $i -eq 30 ]; then
    echo "SSH is still not available after 30 attempts. Exiting."
    rename_ami "FAILED"
    cleanup
    exit 1
  fi
done

# Step 12: Run Goss tests on the instance
echo "Running Goss tests on instance ${INSTANCE_ID}..."

# Copy Goss test file to the instance
echo "Copying Goss test configuration to instance..."
scp -i ${PKR_VAR_PRIVATE_KEY_FILE} \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    "${CURRENT_DIR}/tests/goss.yaml" \
    ${OS_USER}@${HOSTNAME}:~/goss.yaml

# Run Goss tests
echo "Executing Goss validation tests..."
ssh -i ${PKR_VAR_PRIVATE_KEY_FILE} \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    ${OS_USER}@${HOSTNAME} \
    'sudo /usr/local/bin/goss --gossfile ~/goss.yaml validate --format junit > ~/goss-results.xml 2>/dev/null; echo "=== GOSS TEST RESULTS ==="; sudo /usr/local/bin/goss --gossfile ~/goss.yaml validate --format rspecish'

# Copy test results back
echo "Retrieving Goss test results..."
scp -i ${PKR_VAR_PRIVATE_KEY_FILE} \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    ${OS_USER}@${HOSTNAME}:~/goss-results.xml \
    "${CURRENT_DIR}/goss-test-results-$(date +%Y%m%d-%H%M%S).xml" || true

echo "Goss tests completed successfully!"

# Step 13: Rename the AMI to indicate that tests have passed
rename_ami "PASSED"

# Step 14: Check and potentially disable block public access for AMIs
check_block_public_access
disable_image_block_public_access

## # Step 15: Make the AMI public
make_ami_public

# Step 16: Verify the launch permissions of the AMI
verify_launch_permissions

# If the script reaches this point, all operations were successful
SUCCESS=true
