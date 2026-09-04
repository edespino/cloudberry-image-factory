#!/bin/bash
#
# Script Name: packer-build-and-test.sh
#
# Description:
# This script validates, builds, tests, and result-tags a private Amazon
# Machine Image (AMI), including cleanup of its temporary AWS resources.
# An AMI built by this run that fails testing is deregistered and its
# snapshots deleted; pass --keep-failed-ami (or KEEP_FAILED_AMI=1) to keep
# it tagged -FAILED instead. An --existing-ami is never deregistered.
#
# Usage:
# ./packer-build-and-test.sh [OPTIONS]
#
# Options:
#   -p, --private    Keep AMI private (default)
#   --existing-ami ID
#                    Test an approved existing private AMI without building
#   --keep-failed-ami
#                    Keep a failed build's AMI tagged -FAILED instead of
#                    deleting it (also: KEEP_FAILED_AMI=1)
#   -h, --help       Display help message
#
# Prerequisites:
# - AWS CLI configured with appropriate credentials
# - Python 3, AWS CLI, OpenSSH client, nc, curl, and timeout
# - Packer and jq in normal build mode only
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

# Parse command-line options
EXISTING_AMI=""
case "$(printf '%s' "${KEEP_FAILED_AMI:-}" | tr '[:upper:]' '[:lower:]')" in
  1|true|yes) KEEP_FAILED_AMI=true ;;
  *) KEEP_FAILED_AMI=false ;;
esac

# Function to display usage
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -p, --private    Keep AMI private (default)"
  echo "  --existing-ami ID"
  echo "                    Test an approved existing private AMI without building"
  echo "  --keep-failed-ami"
  echo "                    Keep a failed build's AMI tagged -FAILED instead of"
  echo "                    deleting it (also: KEEP_FAILED_AMI=1)"
  echo "  -h, --help       Display this help message"
  echo ""
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--private)
      shift
      ;;
    --existing-ami)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        echo "Error: --existing-ami requires an AMI ID." >&2
        exit 2
      fi
      EXISTING_AMI="$2"
      shift 2
      ;;
    --keep-failed-ami)
      KEEP_FAILED_AMI=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# Function to check if a command is available in the system
# Arguments:
#   $1 - Name of the command to check
command_exists() {
  command -v "$1" &> /dev/null
}

# Check for required commands
REQUIRED_COMMANDS=(aws curl nc python3 scp ssh timeout)
if [ -z "${EXISTING_AMI}" ]; then
  REQUIRED_COMMANDS+=(jq packer)
fi
for cmd in "${REQUIRED_COMMANDS[@]}"; do
  if ! command_exists "$cmd"; then
    echo "$cmd could not be found. Please install $cmd to proceed."
    case "$cmd" in
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
PRIVATE_RUNTIME_HELPER="${SCRIPT_DIR}/private-runtime-key.py"
AMI_METADATA_HELPER="${SCRIPT_DIR}/validate-ami-metadata.py"
for helper in "${PRIVATE_RUNTIME_HELPER}" "${AMI_METADATA_HELPER}"; do
  if [ -L "${helper}" ] || [ ! -f "${helper}" ] || [ ! -x "${helper}" ]; then
    echo "Required helper is missing or not executable." >&2
    exit 1
  fi
done

# Define the path to the Packer HCL file
HCL_FILE="${CURRENT_DIR}/main.pkr.hcl"

# Check if the HCL file exists
if [ ! -f "$HCL_FILE" ]; then
  echo "Error: Packer HCL file not found at ${HCL_FILE}. Aborting."
  exit 1
fi

# Derive CLOUD, FAMILY, and OS_NAME from the directory structure:
#   vm-images/<cloud>/<family>/build/<os>
OS_NAME=$(basename "$CURRENT_DIR")
FAMILY=$(basename "$(dirname "$(dirname "$CURRENT_DIR")")")
CLOUD=$(basename "$(dirname "$(dirname "$(dirname "$CURRENT_DIR")")")")
if [ "$(basename "$(dirname "$CURRENT_DIR")")" != "build" ] || \
   [ "$(basename "$(dirname "$(dirname "$(dirname "$(dirname "$CURRENT_DIR")")")")")" != "vm-images" ]; then
  echo "Error: run from vm-images/<cloud>/<family>/build/<os>/ (got: ${CURRENT_DIR})" >&2
  exit 1
fi
if [ "${CLOUD}" != "aws" ]; then
  echo "Error: no harness exists for cloud '${CLOUD}' (only aws is supported)." >&2
  exit 1
fi
# Determine the correct SSH user based on the OS
case "$OS_NAME" in
    rocky*|rhel*)
        OS_USER="rocky"
        ;;
    centos7*)
        OS_USER="centos"
        ;;
    ubuntu*)
        OS_USER="ubuntu"
        ;;
    debian*)
        OS_USER="admin"
        ;;
    amazon*|amzn*|al2023*|centos10)
        OS_USER="ec2-user"
        ;;
    *)
        OS_USER="rocky"  # Default to rocky for cloudberry builds
        ;;
esac

echo "Using SSH user: ${OS_USER} for OS: ${OS_NAME}"

# Define AWS region and timestamp for unique naming
REGION="us-west-2"                  # Fixed region where the AMI is tested
# Existing-AMI recovery is restricted to this approved account.
EXPECTED_AMI_OWNER="703671893074"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")  # Timestamp for unique resource naming
RUN_NONCE="$(python3 -c 'import secrets; print(secrets.token_hex(12))')"
RUN_ID="${TIMESTAMP}-${RUN_NONCE}"
RUN_TAG_KEY="CloudberryImageFactoryRun"
CLIENT_TOKEN="cloudberry-${RUN_ID}"

AMI_NAME_PREFIX="${FAMILY}-packer-${OS_NAME}-"
if [ -n "${EXISTING_AMI}" ] && [[ ! "${EXISTING_AMI}" =~ ^ami-[0-9a-f]{8,17}$ ]]; then
  echo "Error: existing AMI ID has invalid syntax." >&2
  exit 2
fi

# Variables for AWS resources
export PKR_VAR_KEY_NAME="key-${FAMILY}-${OS_NAME}-${RUN_ID}"  # Name for the temporary key pair
export PKR_VAR_PRIVATE_KEY_FILE=""
PRIVATE_KEY_DIR=""
PRIVATE_RUNTIME_BASE=""
FALLBACK_RUNTIME_CREATED=false
PRIVATE_KEY_FILENAME="${PKR_VAR_KEY_NAME}.pem"
AWS_KEY_PAIR_CREATION_ATTEMPTED=false
SECURITY_GROUP_NAME="${FAMILY}-${OS_NAME}-${RUN_ID}-sg"
SECURITY_GROUP_ID=""
SECURITY_GROUP_CREATION_ATTEMPTED=false
SECURITY_GROUP_DISCOVERY_EXHAUSTED=false
INSTANCE_ID=""
INSTANCE_CREATION_ATTEMPTED=false
INSTANCE_DISCOVERY_EXHAUSTED=false
AMI_ID=""
HOSTNAME=""
AMI_NAME=""
AMI_VALIDATED_FOR_TAGGING=false
AMI_CREATED_BY_RUN=false
CLEANED_UP=false
CLEANUP_STATUS=0

# Variable to track successful execution
SUCCESS=false

# Function to rename the AMI based on the test result
# Arguments:
#   $1 - Result of the test (e.g., "PASSED", "FAILED")
rename_ami() {
  local result=$1
  local base_name="${AMI_NAME}"
  local NEW_NAME
  if [ -n "${AMI_ID}" ] && [ "${AMI_VALIDATED_FOR_TAGGING}" = true ]; then
    while [[ "${base_name}" =~ -(PASSED|FAILED)$ ]]; do
      base_name="${base_name%-${BASH_REMATCH[1]}}"
    done
    NEW_NAME="${base_name}-${result}"
    echo "Renaming AMI to indicate ${result}: ${NEW_NAME}"
    bounded_aws 15 ec2 create-tags \
      --resources "${AMI_ID}" \
      --tags "Key=Name,Value=${NEW_NAME}" \
      --region "${REGION}"
  fi
}

# Function to clean up resources
bounded_aws() {
  local limit_seconds="$1"
  shift
  timeout --signal=TERM --kill-after=1s "${limit_seconds}s" aws "$@"
}

quiet_bounded_aws() {
  local limit_seconds="$1"
  shift
  bounded_aws "${limit_seconds}" "$@" > /dev/null 2>&1
}

normalize_aws_text() {
  local value="$1"
  if [ "${value}" = "None" ] || [ "${value}" = "null" ]; then
    value=""
  fi
  printf '%s' "${value}"
}

discover_security_group() {
  local attempt
  local discovered=""
  for attempt in 1 2; do
    discovered="$(
      bounded_aws 10 ec2 describe-security-groups \
        --filters \
          "Name=group-name,Values=${SECURITY_GROUP_NAME}" \
          "Name=tag:${RUN_TAG_KEY},Values=${RUN_ID}" \
        --query "SecurityGroups[0].GroupId" \
        --output "text" \
        --region "${REGION}" 2>/dev/null
    )" || discovered=""
    discovered="$(normalize_aws_text "${discovered}")"
    if [[ "${discovered}" =~ ^sg-[0-9A-Za-z-]+$ ]]; then
      printf '%s' "${discovered}"
      return 0
    fi
    [ "${attempt}" -eq 2 ] || sleep 1
  done
  return 1
}

discover_instance() {
  local attempt
  local discovered=""
  for attempt in 1 2; do
    discovered="$(
      bounded_aws 10 ec2 describe-instances \
        --filters \
          "Name=tag:${RUN_TAG_KEY},Values=${RUN_ID}" \
          "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output "text" \
        --region "${REGION}" 2>/dev/null
    )" || discovered=""
    discovered="$(normalize_aws_text "${discovered}")"
    if [[ "${discovered}" =~ ^i-[0-9A-Za-z-]+$ ]]; then
      printf '%s' "${discovered}"
      return 0
    fi
    [ "${attempt}" -eq 2 ] || sleep 1
  done
  return 1
}

cleanup() {
  if [ "$CLEANED_UP" = true ]; then
    return "${CLEANUP_STATUS}"
  fi
  CLEANED_UP=true
  trap - ERR
  set +e
  if [ "${AWS_KEY_PAIR_CREATION_ATTEMPTED}" = true ]; then
    AWS_KEY_PAIR_CREATION_ATTEMPTED=false
    if ! quiet_bounded_aws 5 ec2 delete-key-pair \
      --key-name "${PKR_VAR_KEY_NAME}" --region "${REGION}"; then
      echo "WARNING: key pair deletion attempt failed." >&2
      CLEANUP_STATUS=1
    fi
    echo "Key pair deletion attempted for ${PKR_VAR_KEY_NAME}"
  fi
  echo "Cleaning up..."
  if [ -z "${INSTANCE_ID}" ] \
    && [ "${INSTANCE_CREATION_ATTEMPTED}" = true ] \
    && [ "${INSTANCE_DISCOVERY_EXHAUSTED}" = false ]; then
    INSTANCE_ID="$(discover_instance 2>/dev/null)" || INSTANCE_ID=""
  fi
  INSTANCE_ID="$(normalize_aws_text "${INSTANCE_ID}")"
  if [ -n "${INSTANCE_ID}" ]; then
    echo "Terminating the EC2 instance..."
    termination_ok=true
    if ! quiet_bounded_aws 30 ec2 terminate-instances \
      --instance-ids "${INSTANCE_ID}" --region "${REGION}"; then
      echo "WARNING: instance termination request failed for ${INSTANCE_ID}." >&2
      termination_ok=false
      CLEANUP_STATUS=1
    fi
    if ! quiet_bounded_aws 300 ec2 wait instance-terminated \
      --instance-ids "${INSTANCE_ID}" --region "${REGION}"; then
      echo "WARNING: instance termination was not verified for ${INSTANCE_ID}." >&2
      termination_ok=false
      CLEANUP_STATUS=1
    fi
    if [ "${termination_ok}" = true ]; then
      echo "EC2 instance ${INSTANCE_ID} terminated successfully."
    fi
  elif [ "${INSTANCE_CREATION_ATTEMPTED}" = true ]; then
    echo "WARNING: temporary instance could not be discovered for cleanup." >&2
    CLEANUP_STATUS=1
  fi
  if [ -n "${PKR_VAR_PRIVATE_KEY_FILE}" ] && [ -f "${PKR_VAR_PRIVATE_KEY_FILE}" ]; then
    echo "Removing key file ${PKR_VAR_PRIVATE_KEY_FILE}"
    if ! rm -f -- "${PKR_VAR_PRIVATE_KEY_FILE}"; then
      echo "WARNING: local private key removal failed." >&2
      CLEANUP_STATUS=1
    fi
  fi
  if [ -n "${PRIVATE_KEY_DIR}" ]; then
    rmdir -- "${PRIVATE_KEY_DIR}" 2>/dev/null || true
  fi
  if [ "${FALLBACK_RUNTIME_CREATED}" = true ] && [ -n "${PRIVATE_RUNTIME_BASE}" ]; then
    rmdir -- "${PRIVATE_RUNTIME_BASE}" 2>/dev/null || true
  fi
  if [ -z "${SECURITY_GROUP_ID}" ] \
    && [ "${SECURITY_GROUP_CREATION_ATTEMPTED}" = true ] \
    && [ "${SECURITY_GROUP_DISCOVERY_EXHAUSTED}" = false ]; then
    SECURITY_GROUP_ID="$(discover_security_group 2>/dev/null)" || SECURITY_GROUP_ID=""
  fi
  SECURITY_GROUP_ID="$(normalize_aws_text "${SECURITY_GROUP_ID}")"
  if [ -n "${SECURITY_GROUP_ID}" ]; then
    echo "Deleting security group ${SECURITY_GROUP_ID}"
    security_group_deleted=false
    for attempt in 1 2 3; do
      if quiet_bounded_aws 30 ec2 delete-security-group \
        --group-id "${SECURITY_GROUP_ID}" --region "${REGION}"; then
        security_group_deleted=true
        break
      fi
      echo "WARNING: security group delete attempt ${attempt} failed." >&2
      sleep 1
    done
    remaining_security_groups="$(
      bounded_aws 15 ec2 describe-security-groups \
        --filters "Name=group-id,Values=${SECURITY_GROUP_ID}" \
        --query "length(SecurityGroups)" --output "text" \
        --region "${REGION}" 2>/dev/null
    )"
    verification_status=$?
    if [ "${verification_status}" -ne 0 ]; then
      echo "WARNING: security group deletion could not be verified." >&2
      CLEANUP_STATUS=1
    elif [ "${remaining_security_groups}" != "0" ]; then
      echo "WARNING: security group ${SECURITY_GROUP_ID} still exists." >&2
      CLEANUP_STATUS=1
    elif [ "${security_group_deleted}" != true ]; then
      echo "Security group ${SECURITY_GROUP_ID} is confirmed absent."
    fi
  elif [ "${SECURITY_GROUP_CREATION_ATTEMPTED}" = true ]; then
    echo "WARNING: temporary security group could not be discovered for cleanup." >&2
    CLEANUP_STATUS=1
  fi
  if [ "${CLEANUP_STATUS}" -eq 0 ]; then
    echo "Cleanup completed."
  else
    echo "WARNING: cleanup did not complete successfully." >&2
  fi

  # Print final success message if everything was successful
  if [ "$SUCCESS" = true ] && [ "${CLEANUP_STATUS}" -eq 0 ]; then
    echo "-----------------------------------"
    echo "AMI Build and Test Completed"
    echo "-----------------------------------"
    echo "AMI ID: ${AMI_ID}"
    echo "AMI Name: ${AMI_NAME}"
    echo "Region: ${REGION}"
    echo "This AMI has passed all tests and remains private."
    echo "-----------------------------------"
  fi
  return "${CLEANUP_STATUS}"
}

# Tag the AMI's Name as -FAILED (bounded; never blocks cleanup). Used when
# a failed AMI is kept: --keep-failed-ami, --existing-ami, or as the fallback
# when discarding fails.
tag_failed_ami() {
  local base_name="${AMI_NAME}"
  local NEW_NAME
  while [[ "${base_name}" =~ -(PASSED|FAILED)$ ]]; do
    base_name="${base_name%-${BASH_REMATCH[1]}}"
  done
  NEW_NAME="${base_name}-FAILED"
  echo "Renaming AMI to indicate FAILED: ${NEW_NAME}"
  quiet_bounded_aws 5 ec2 create-tags \
    --resources "${AMI_ID}" \
    --tags "Key=Name,Value=${NEW_NAME}" \
    --region "${REGION}"
}

# Deregister the AMI this run built and delete its snapshots. Only called
# for AMIs created by this run (never --existing-ami). Snapshot ids are read
# before deregistering because the image cannot be described afterwards.
# Returns non-zero, so the caller tags -FAILED and the cleanup workflow later
# deletes image and snapshots together, when the image name is not this
# target's, when the snapshot ids cannot be read (deregistering then would
# orphan them silently), or when deregistration fails. A snapshot that fails
# to delete after deregistration is reported by id; it must be removed by
# hand, since the cleanup workflow's orphan scan matches on snapshot
# descriptions that Packer-created snapshots do not carry.
discard_failed_ami() {
  local snapshots_text snapshot
  local -a snapshots=()
  if [[ "${AMI_NAME}" != "${AMI_NAME_PREFIX}"* ]]; then
    echo "WARNING: refusing to discard ${AMI_ID}: name '${AMI_NAME}' is outside ${AMI_NAME_PREFIX}*; tagging it -FAILED instead." >&2
    return 1
  fi
  echo "Discarding failed AMI ${AMI_ID} (use --keep-failed-ami or KEEP_FAILED_AMI=1 to keep it tagged -FAILED)."
  if ! snapshots_text="$(
    bounded_aws 15 ec2 describe-images \
      --image-ids "${AMI_ID}" \
      --query "Images[0].BlockDeviceMappings[?Ebs.SnapshotId!=null].Ebs.SnapshotId" \
      --output "text" \
      --region "${REGION}" 2>/dev/null
  )"; then
    echo "WARNING: could not read the snapshot ids of ${AMI_ID}; tagging it -FAILED instead of orphaning them." >&2
    return 1
  fi
  snapshots_text="$(normalize_aws_text "${snapshots_text}")"
  read -r -a snapshots <<< "${snapshots_text}"
  if ! quiet_bounded_aws 15 ec2 deregister-image \
    --image-id "${AMI_ID}" --region "${REGION}"; then
    echo "WARNING: could not deregister failed AMI ${AMI_ID}; tagging it -FAILED instead." >&2
    return 1
  fi
  echo "Deregistered failed AMI ${AMI_ID}."
  for snapshot in ${snapshots[@]+"${snapshots[@]}"}; do
    if [[ ! "${snapshot}" =~ ^snap-[0-9a-f]+$ ]]; then
      echo "WARNING: ignoring unexpected snapshot id '${snapshot}' for ${AMI_ID}." >&2
      continue
    fi
    if quiet_bounded_aws 15 ec2 delete-snapshot \
      --snapshot-id "${snapshot}" --region "${REGION}"; then
      echo "Deleted snapshot ${snapshot}."
    else
      echo "WARNING: could not delete snapshot ${snapshot} of failed AMI ${AMI_ID}; it is orphaned and must be removed by hand." >&2
    fi
  done
  return 0
}

# Error handler: clean up, then discard (or tag) the failed AMI
error_handler() {
  echo "An error occurred. Running cleanup and discarding or tagging the AMI if necessary."
  trap - ERR
  cleanup || true
  if [ -n "${AMI_ID}" ] && [ "${AMI_VALIDATED_FOR_TAGGING}" = true ]; then
    if [ "${AMI_CREATED_BY_RUN}" = true ] && [ "${KEEP_FAILED_AMI}" != true ]; then
      discard_failed_ami || tag_failed_ami
    else
      tag_failed_ami
    fi
  fi
  exit 1
}

# Trap errors and EXIT signals to ensure cleanup is performed
on_exit() {
  local original_status=$?
  local cleanup_status
  trap - EXIT ERR
  cleanup
  cleanup_status=$?
  if [ "${original_status}" -eq 0 ] && [ "${cleanup_status}" -ne 0 ]; then
    original_status="${cleanup_status}"
  fi
  exit "${original_status}"
}
trap on_exit EXIT
trap error_handler ERR

if [ -n "${EXISTING_AMI}" ]; then
  AMI_ID="${EXISTING_AMI}"
  echo "Validating existing private AMI metadata..."
  AMI_NAME="$(
    aws ec2 describe-images \
      --image-ids "${AMI_ID}" \
      --region "${REGION}" \
      --output "json" |
      "${AMI_METADATA_HELPER}" \
        "${AMI_ID}" "${EXPECTED_AMI_OWNER}" "${AMI_NAME_PREFIX}"
  )"
  AMI_VALIDATED_FOR_TAGGING=true
fi

# Step 1: Create a new key pair for SSH access
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
  FALLBACK_RUNTIME_CREATED=true
fi
PRIVATE_KEY_DIR="$("${PRIVATE_RUNTIME_HELPER}" create)"
if [ "${FALLBACK_RUNTIME_CREATED}" = true ]; then
  PRIVATE_RUNTIME_BASE="$(dirname -- "${PRIVATE_KEY_DIR}")"
  export XDG_RUNTIME_DIR="${PRIVATE_RUNTIME_BASE}"
fi
PRIVATE_KEY_DIRECTORY_NAME="$(basename -- "${PRIVATE_KEY_DIR}")"
export PKR_VAR_PRIVATE_KEY_FILE="${PRIVATE_KEY_DIR}/${PRIVATE_KEY_FILENAME}"
echo "Creating new key pair..."
AWS_KEY_PAIR_CREATION_ATTEMPTED=true
aws ec2 create-key-pair --key-name "${PKR_VAR_KEY_NAME}" --query 'KeyMaterial' --output text --region "${REGION}" |
  "${PRIVATE_RUNTIME_HELPER}" write "${PRIVATE_KEY_DIRECTORY_NAME}" "${PRIVATE_KEY_FILENAME}"
echo "Created key pair ${PKR_VAR_KEY_NAME} and saved to ${PKR_VAR_PRIVATE_KEY_FILE}"

if [ -z "${EXISTING_AMI}" ]; then
  # Step 2: Initialize Packer plugins
  echo "Initializing Packer plugins..."
  if ! packer init "${HCL_FILE}"; then
    echo "Packer plugin initialization failed. Aborting."
    error_handler
  fi

  # Step 3: Validate the Packer template
  echo "Validating Packer template..."
  if ! packer validate \
    -var "family=${FAMILY}" \
    -var "os_name=${OS_NAME}" \
    -var "region=${REGION}" \
    "${HCL_FILE}"; then
    echo "Packer template validation failed. Aborting."
    error_handler
  fi

  # Step 4: Build the AMI using the Packer template
  echo "Building the Packer template..."
  packer build \
    -var "family=${FAMILY}" \
    -var "os_name=${OS_NAME}" \
    -var "region=${REGION}" \
    "${HCL_FILE}"

  # Step 5: Parse the AMI ID from the Packer manifest file
  echo "Parsing the AMI ID from packer-manifest.json..."
  AMI_ID="$(jq -r '.builds[-1].artifact_id' "packer-manifest.json" | cut -d':' -f2)"
  AMI_CREATED_BY_RUN=true

  # Step 6: Retrieve the AMI name
  AMI_NAME="$(
    aws ec2 describe-images \
      --image-ids "${AMI_ID}" \
      --query "Images[*].Name" \
      --output "text" \
      --region "${REGION}"
  )"
  AMI_VALIDATED_FOR_TAGGING=true
fi

# Step 6b: Pick the goss test instance type from the AMI architecture
# (arm64 AMIs cannot launch on t3; Graviton t4g is the arm64 equivalent).
AMI_ARCHITECTURE="$(
  aws ec2 describe-images \
    --image-ids "${AMI_ID}" \
    --query "Images[0].Architecture" \
    --output "text" \
    --region "${REGION}"
)"
if [ "${AMI_ARCHITECTURE}" = "arm64" ]; then
  TEST_INSTANCE_TYPE="t4g.medium"
else
  TEST_INSTANCE_TYPE="t3.medium"
fi
echo "AMI architecture: ${AMI_ARCHITECTURE}; test instance type: ${TEST_INSTANCE_TYPE}"

# Step 7: Retrieve local IP address to restrict SSH access to the current machine
if ! PUBLIC_IP="$(
  curl --fail --silent --show-error \
    --connect-timeout 5 --max-time 10 \
    "https://checkip.amazonaws.com"
)"; then
  echo "Unable to determine the public IPv4 address." >&2
  error_handler
fi
if [[ ! "${PUBLIC_IP}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "Public IP response is not exactly one plain IPv4 address." >&2
  error_handler
fi
IFS='.' read -r -a PUBLIC_IP_OCTETS <<< "${PUBLIC_IP}"
for octet in "${PUBLIC_IP_OCTETS[@]}"; do
  if (( 10#${octet} > 255 )); then
    echo "Public IP response contains an invalid IPv4 octet." >&2
    error_handler
  fi
done
LOCAL_CIDR="${PUBLIC_IP}/32"

# Step 8: Create a new security group to allow SSH access
echo "Creating new security group..."
SECURITY_GROUP_CREATION_ATTEMPTED=true
if ! SECURITY_GROUP_ID="$(
  aws ec2 create-security-group \
    --group-name "${SECURITY_GROUP_NAME}" \
    --description "Security group for ${OS_NAME} ${FAMILY}" \
    --tag-specifications \
      "ResourceType=security-group,Tags=[{Key=${RUN_TAG_KEY},Value=${RUN_ID}}]" \
    --region "${REGION}" --query "GroupId" --output "text"
)"; then
  if ! SECURITY_GROUP_ID="$(discover_security_group 2>/dev/null)"; then
    SECURITY_GROUP_ID=""
    SECURITY_GROUP_DISCOVERY_EXHAUSTED=true
  fi
fi
if [[ ! "${SECURITY_GROUP_ID}" =~ ^sg-[0-9A-Za-z-]+$ ]]; then
  echo "Unable to identify the temporary security group." >&2
  error_handler
fi
aws ec2 authorize-security-group-ingress \
  --group-id "${SECURITY_GROUP_ID}" \
  --protocol "tcp" --port "22" --cidr "${LOCAL_CIDR}" --region "${REGION}"
echo "Created security group ${SECURITY_GROUP_ID} with SSH access for CIDR ${LOCAL_CIDR}"

# Step 9: Start a new EC2 instance using the created AMI
echo "Starting a new EC2 instance..."
INSTANCE_CREATION_ATTEMPTED=true
run_test_instance() {
  aws ec2 run-instances \
    --image-id "${AMI_ID}" \
    --instance-type "${TEST_INSTANCE_TYPE}" \
    --key-name "${PKR_VAR_KEY_NAME}" \
    --security-group-ids "${SECURITY_GROUP_ID}" \
    --client-token "${CLIENT_TOKEN}" \
    --tag-specifications \
      "ResourceType=instance,Tags=[{Key=${RUN_TAG_KEY},Value=${RUN_ID}}]" \
    --query "Instances[0].InstanceId" \
    --output "text" \
    --region "${REGION}"
}
if ! INSTANCE_ID="$(run_test_instance)"; then
  # The client token makes this retry idempotent if AWS created the instance
  # but the first response was lost.
  if ! INSTANCE_ID="$(run_test_instance)"; then
    if ! INSTANCE_ID="$(discover_instance 2>/dev/null)"; then
      INSTANCE_ID=""
      INSTANCE_DISCOVERY_EXHAUSTED=true
    fi
  fi
fi
INSTANCE_ID="$(normalize_aws_text "${INSTANCE_ID}")"
if [[ ! "${INSTANCE_ID}" =~ ^i-[0-9A-Za-z-]+$ ]]; then
  echo "Unable to identify the temporary test instance." >&2
  error_handler
fi

# Step 10: Wait until the instance is in the running state
echo "Waiting for the instance to be in running state..."
aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}" --region "${REGION}"

# Step 11: Retrieve the public DNS name of the instance
HOSTNAME="$(
  aws ec2 describe-instances \
    --instance-ids "${INSTANCE_ID}" \
    --query "Reservations[*].Instances[*].PublicDnsName" \
    --output "text" \
    --region "${REGION}"
)"

# Step 12: Loop until SSH access is available on the instance
echo "Waiting for SSH to become available on ${HOSTNAME}..."
for ((i=1; i<=30; i++)); do
  if nc -zv "${HOSTNAME}" "22" 2>&1 | grep -q 'succeeded'; then
    echo "SSH is available on ${HOSTNAME}"
    break
  else
    echo "SSH is not available yet. Retry $i/30..."
    sleep $((i*2))
  fi

  if [ $i -eq 30 ]; then
    echo "SSH is still not available after 30 attempts. Exiting."
    error_handler
  fi
done

# Step 13: Run Goss tests on the instance
echo "Running Goss tests on instance ${INSTANCE_ID}..."

# Copy Goss test files to the instance (including common tests)
echo "Copying Goss test configuration to instance..."

# Create directory structure on the instance to match source layout
ssh -i "${PKR_VAR_PRIVATE_KEY_FILE}" \
    -o "StrictHostKeyChecking=no" \
    -o "UserKnownHostsFile=/dev/null" \
    -o "LogLevel=ERROR" \
    "${OS_USER}@${HOSTNAME}" \
    "mkdir -p ~/${OS_NAME}/tests ~/common/tests"

# Copy common test files
if [ -d "${SCRIPT_DIR}/../common/tests" ]; then
    echo "Copying common test files..."
    scp -i "${PKR_VAR_PRIVATE_KEY_FILE}" \
        -o "StrictHostKeyChecking=no" \
        -o "UserKnownHostsFile=/dev/null" \
        -o "LogLevel=ERROR" \
        "${SCRIPT_DIR}/../common/tests/"*.yaml \
        "${OS_USER}@${HOSTNAME}:~/common/tests/"
fi

# Copy platform-specific Goss test file
scp -i "${PKR_VAR_PRIVATE_KEY_FILE}" \
    -o "StrictHostKeyChecking=no" \
    -o "UserKnownHostsFile=/dev/null" \
    -o "LogLevel=ERROR" \
    "${CURRENT_DIR}/tests/goss.yaml" \
    "${OS_USER}@${HOSTNAME}:~/${OS_NAME}/tests/goss.yaml"

# Run Goss tests
echo "Executing Goss validation tests..."
ssh -i "${PKR_VAR_PRIVATE_KEY_FILE}" \
    -o "StrictHostKeyChecking=no" \
    -o "UserKnownHostsFile=/dev/null" \
    -o "LogLevel=ERROR" \
    "${OS_USER}@${HOSTNAME}" \
    "sudo /usr/local/bin/goss --gossfile ~/${OS_NAME}/tests/goss.yaml validate --format junit > ~/goss-results.xml 2>/dev/null; echo '=== GOSS TEST RESULTS ==='; sudo /usr/local/bin/goss --gossfile ~/${OS_NAME}/tests/goss.yaml validate --format rspecish"

# Copy test results back
echo "Retrieving Goss test results..."
scp -i "${PKR_VAR_PRIVATE_KEY_FILE}" \
    -o "StrictHostKeyChecking=no" \
    -o "UserKnownHostsFile=/dev/null" \
    -o "LogLevel=ERROR" \
    "${OS_USER}@${HOSTNAME}:~/goss-results.xml" \
    "${CURRENT_DIR}/goss-test-results-$(date +%Y%m%d-%H%M%S).xml" || true

echo "Goss tests completed successfully!"

# Step 14: Rename the AMI to indicate that tests have passed
rename_ami "PASSED"

echo "Keeping AMI private."

# If the script reaches this point, all operations were successful
SUCCESS=true
