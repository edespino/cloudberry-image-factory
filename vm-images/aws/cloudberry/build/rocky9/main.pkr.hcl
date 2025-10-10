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

source "amazon-ebs" "base-cbdb-build-image" {
  access_key    = var.aws_access_key
  secret_key    = var.aws_secret_key
  token         = var.aws_session_token
  region        = var.region

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

  ami_name = format("cloudberry-packer-%s-%s-%s", var.vm_type, var.os_name, formatdate("YYYYMMDD-HHmmss", timestamp()))
  ami_description = "Apache Cloudberry (Incubating) Build - Rocky Linux 9 Base AMI built via Packer"

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size          = 24
    volume_type          = "gp2"
    delete_on_termination = true
  }
}

build {
  sources = ["source.amazon-ebs.base-cbdb-build-image"]

  provisioner "shell" {
    script = "scripts/system_add_cbdb_build_rpm_dependencies.sh"
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
    script = "../common/scripts/system_add_dbadmin_ulimits.sh"
    environment_vars = [
      "DB_USERNAME=cbadmin"
    ]
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_yq.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_awscli.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_set_timezone.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_golang.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_cbdb_xerces_c_build_dependency.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_config_java_home.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_config_starship_prompt.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_disable_selinux.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_kernel_configs.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_swap.sh"
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

  provisioner "shell" {
    script = "../common/scripts/system_add_cloudberry_motd.sh"
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

  provisioner "shell" {
    script = "../common/scripts/system_add_docker.sh"
  }

  post-processors {
    post-processor "manifest" {
      output = "packer-manifest.json"
    }
  }
}
