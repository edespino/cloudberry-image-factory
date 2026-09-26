packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.6"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "family" {
  type = string
}

variable "os_name" {
  type    = string
}

variable "default_username" {
  type    = string
  default = "ec2-user"
}

variable "custom_shell_commands" {
  type    = list(string)
  default = []
}

variable "region" {
  type    = string
  default = ""
}

# The Purpose=ami-build subnet, passed by packer-build-and-test.sh with -var so
# no environment or .pkrvars.hcl value can override it. The build account has
# no default VPC; the empty default only serves packer validate. Credentials
# come only from the AWS SDK chain the harness checks (no credential variables).
variable "subnet_id" {
  type    = string
  default = ""
}

source "amazon-ebs" "base-build-image" {
  region        = var.region
  # Session Manager access only: the builder gets no public IP and no inbound
  # rule. It runs in the private Purpose=ami-build subnet with the stack's
  # ami-build-ssm instance profile and no-inbound ami-build-builder security
  # group (infra/engineering-ami-build.cfn.yaml).
  subnet_id                   = var.subnet_id
  associate_public_ip_address = false
  ssh_interface               = "session_manager"
  iam_instance_profile        = "ami-build-ssm"
  pause_before_ssm            = "30s"
  security_group_filter {
    filters = {
      "group-name" = "ami-build-builder"
    }
  }

  # The account's SCP denies RunInstances unless IMDSv2 is required
  # (RequireImdsv2OnLaunch); Packer's default request sends HttpTokens=optional.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  instance_type = "t3.2xlarge"

  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023.*-kernel-6.1-x86_64"
      virtualization-type = "hvm"
    }
    owners      = ["137112412989"]
    most_recent = true
  }

  ssh_username         = "ec2-user"
  # Remove Packer's temporary public key from authorized_keys before capture.
  ssh_clear_authorized_keys = true

  # Omit ami_description: it would call denied ModifyImageAttribute.
  ami_name = format("%s-packer-%s-%s", var.family, var.os_name, formatdate("YYYYMMDD-HHmmss", timestamp()))

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 100
    volume_type           = "gp3"
    delete_on_termination = true
  }
}

build {
  sources = ["source.amazon-ebs.base-build-image"]

  # Configure DNF for resilient package operations (must run first)
  provisioner "shell" {
    script = "../../../../common/scripts/system_configure_dnf.sh"
  }

  # Install platform-specific dependencies
  provisioner "shell" {
    script = "scripts/system_add_synxdb_cloud_dependencies.sh"
  }

  # System configuration
  provisioner "shell" {
    script = "../../../../common/scripts/system_set_timezone.sh"
  }

  # Create gpadmin user
  provisioner "shell" {
    script = "../../../../common/scripts/system_adduser_dbadmin.sh"
    environment_vars = [
      "DB_USERNAME=gpadmin"
    ]
  }

  # Create cbadmin user
  provisioner "shell" {
    script = "../../../../common/scripts/system_adduser_dbadmin.sh"
    environment_vars = [
      "DB_USERNAME=cbadmin"
    ]
  }

  # Install operational tools
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_docker.sh"
  }

  provisioner "shell" {
    script = "../../../../common/scripts/system_add_helm_kubectl.sh"
  }

  provisioner "shell" {
    script = "../../../../common/scripts/system_add_gh.sh"
  }

  # Install glow (terminal markdown viewer, Charm repo)
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_glow.sh"
  }

  provisioner "shell" {
    script = "../../../../common/scripts/system_config_starship_prompt.sh"
  }

  # Configure user environments
  provisioner "shell" {
    script = "../../../../common/scripts/dbadmin_configure_environment.sh"
    environment_vars = [
      "DB_USERNAME=gpadmin"
    ]
  }

  provisioner "shell" {
    script = "../../../../common/scripts/dbadmin_configure_environment.sh"
    environment_vars = [
      "DB_USERNAME=cbadmin"
    ]
  }

  # Configure MOTD with Synx template
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_motd_manager.sh"
    environment_vars = [
      "MOTD_TEMPLATE=synx"
    ]
  }

  # Install Goss testing framework (near the end; image capture cleanup runs last)
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_goss.sh"
  }

  # Per-instance gpadmin/cbadmin SSH keys, generated at first boot.
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_dbadmin_ssh_keygen.sh"
  }

  # Last provisioner: clear build-instance SSM agent and cloud-init state
  # before the image is captured.
  provisioner "shell" {
    script = "../../../../common/scripts/system_prepare_image_capture.sh"
  }

  post-processors {
    post-processor "manifest" {
      output = "packer-manifest.json"
    }
  }
}
