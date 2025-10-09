packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.6"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "vm_type" {
  type    = string
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

source "amazon-ebs" "base-cbdb-build-image" {
  access_key    = var.aws_access_key
  secret_key    = var.aws_secret_key
  token         = var.aws_session_token
  region        = var.region

  instance_type = "t3.2xlarge"

  source_ami_filter {
    filters = {
      name                = "al2023-ami-minimal-2023.*-kernel-6.1-x86_64"
      virtualization-type = "hvm"
    }
    owners      = ["137112412989"]
    most_recent = true
  }

  ssh_username         = "ec2-user"

  ami_name = format("cloudberry-packer-%s-%s-%s", var.vm_type, var.os_name, formatdate("YYYYMMDD-HHmmss", timestamp()))
  ami_description = "Apache Cloudberry (Incubating) Build - Amazon Linux 2023 (al2023) Base AMI built via Packer"

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 100
    volume_type           = "gp3"
    delete_on_termination = true
  }
}

build {
  sources = ["source.amazon-ebs.base-cbdb-build-image"]

  provisioner "shell" {
    script = "scripts/system_add_cbdb_build_rpm_dependencies.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_set_timezone.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_cbdb_xerces_c_build_dependency.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_golang.sh"
  }

  # Create gpadmin user first
  provisioner "shell" {
    script = "../common/scripts/system_adduser_dbadmin.sh"
    environment_vars = [
      "DB_USERNAME=gpadmin"
    ]
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_dbadmin_ulimits.sh"
    environment_vars = [
      "DB_USERNAME=gpadmin"
    ]
  }

  # Create cbadmin user second
  provisioner "shell" {
    script = "../common/scripts/system_adduser_dbadmin.sh"
    environment_vars = [
      "DB_USERNAME=cbadmin"
    ]
  }

  provisioner "shell" {
    script = "scripts/system_add_docker.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_dbadmin_ulimits.sh"
    environment_vars = [
      "DB_USERNAME=cbadmin"
    ]
  }

  provisioner "shell" {
    script = "../common/scripts/system_disable_selinux.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_kernel_configs.sh"
  }

  # Configure gpadmin environment
  provisioner "shell" {
    script = "../common/scripts/dbadmin_configure_environment.sh"
    environment_vars = [
      "DB_USERNAME=gpadmin"
    ]
  }

  # Configure cbadmin environment
  provisioner "shell" {
    script = "../common/scripts/dbadmin_configure_environment.sh"
    environment_vars = [
      "DB_USERNAME=cbadmin"
    ]
  }

  # Install Claude CLI for gpadmin
  provisioner "shell" {
    script = "../common/scripts/system_add_claude.sh"
    environment_vars = [
      "DB_USERNAME=gpadmin"
    ]
  }

  # Install Claude CLI for cbadmin
  provisioner "shell" {
    script = "../common/scripts/system_add_claude.sh"
    environment_vars = [
      "DB_USERNAME=cbadmin"
    ]
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_goss.sh"
  }

  post-processors {
    post-processor "manifest" {
      output = "packer-manifest.json"
    }
  }
}
