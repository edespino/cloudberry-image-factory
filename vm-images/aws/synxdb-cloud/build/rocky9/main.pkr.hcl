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
  default = "rocky"
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
      name                = "Rocky-9-EC2-Base-9.*-*.x86_64"
      virtualization-type = "hvm"
    }
    owners      = ["792107900819"]
    most_recent = true
  }

  ssh_username         = "rocky"

  # Omit ami_description: it would call denied ModifyImageAttribute.
  ami_name = format("%s-packer-%s-%s", var.family, var.os_name, formatdate("YYYYMMDD-HHmmss", timestamp()))

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 24
    volume_type           = "gp2"
    delete_on_termination = true
  }
}

build {
  sources = ["source.amazon-ebs.base-build-image"]

  # Configure DNF for resilient package operations (must run first)
  provisioner "shell" {
    script = "../../../../common/scripts/system_configure_dnf.sh"
  }

  provisioner "shell" {
    script = "scripts/system_add_synxdb_cloud_dependencies.sh"
  }

  # Install Python dependencies system-wide (omnistrate-cli-tools + synxdb-cli)
  provisioner "shell" {
    inline = [
      "sudo python3 -m pip install 'rich>=13.0.0' 'click>=8.0.0' 'pyyaml>=6.0.0' 'pydantic>=2.0.0' 'pydantic-settings>=2.0.0' 'boto3>=1.28.0' 'readchar>=4.0.0' 'typer>=0.9.0' 'httpx>=0.25.0'"
    ]
  }

  # Create gpadmin user first
  provisioner "shell" {
    script = "../../../../common/scripts/system_adduser_dbadmin.sh"
    environment_vars = [
      "DB_USERNAME=gpadmin"
    ]
  }

  # Create cbadmin user second
  provisioner "shell" {
    script = "../../../../common/scripts/system_adduser_dbadmin.sh"
    environment_vars = [
      "DB_USERNAME=cbadmin"
    ]
  }

  provisioner "shell" {
    script = "../../../../common/scripts/system_add_yq.sh"
  }

  provisioner "shell" {
    script = "../../../../common/scripts/system_add_awscli.sh"
  }

  provisioner "shell" {
    script = "../../../../common/scripts/system_set_timezone.sh"
  }

  provisioner "shell" {
    script = "../../../../common/scripts/system_config_starship_prompt.sh"
  }

  provisioner "shell" {
    script = "../../../../common/scripts/system_add_swap.sh"
  }

  # Configure gpadmin environment
  provisioner "shell" {
    script = "../../../../common/scripts/dbadmin_configure_environment.sh"
    environment_vars = [
      "DB_USERNAME=gpadmin"
    ]
  }

  # Configure cbadmin environment
  provisioner "shell" {
    script = "../../../../common/scripts/dbadmin_configure_environment.sh"
    environment_vars = [
      "DB_USERNAME=cbadmin"
    ]
  }

  provisioner "shell" {
    script = "../../../../common/scripts/system_add_gh.sh"
  }

  provisioner "shell" {
    script = "../../../../common/scripts/system_add_helm_kubectl.sh"
  }

  provisioner "shell" {
    script = "../../../../common/scripts/system_add_omnistrate_ctl.sh"
  }

  provisioner "shell" {
    script = "../../../../common/scripts/system_add_motd_manager.sh"
    environment_vars = [
      "MOTD_TEMPLATE=synx"
    ]
  }

  provisioner "shell" {
    script = "../../../../common/scripts/system_add_goss.sh"
  }

  provisioner "shell" {
    script = "../../../../common/scripts/system_add_docker.sh"
  }

  post-processors {
    post-processor "manifest" {
      output = "packer-manifest.json"
    }
  }
}
