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

variable "aws_access_key" {
  type    = string
  default = ""
}

variable "aws_secret_key" {
  type    = string
  default = ""
}

variable "aws_session_token" {
  type    = string
  default = ""
}

variable "region" {
  type    = string
  default = ""
}

source "amazon-ebs" "base-build-image" {
  access_key    = var.aws_access_key
  secret_key    = var.aws_secret_key
  token         = var.aws_session_token
  region        = var.region
  temporary_security_group_source_public_ip = true

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

  # Install Goss testing framework (must be last)
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_goss.sh"
  }

  post-processors {
    post-processor "manifest" {
      output = "packer-manifest.json"
    }
  }
}
