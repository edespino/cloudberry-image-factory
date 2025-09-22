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
  default = "ubuntu"
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
      name                = "*ubuntu-jammy-22.04-amd64-minimal-2025*"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"]
    most_recent = true
  }

  ssh_username         = "ubuntu"

  ami_name = format("cloudberry-packer-%s-%s-%s", var.vm_type, var.os_name, formatdate("YYYYMMDD-HHmmss", timestamp()))
  ami_description = "Apache Cloudberry (Incubating) Build - Ubuntu 22.04 Base AMI built via Packer"

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
    script = "scripts/system_add_cbdb_build_deb_dependencies.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_set_timezone.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_golang.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_yq.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_kernel_configs.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_adduser_cbadmin.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_cbadmin_ulimits.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/cbadmin_configure_environment.sh"
  }

  provisioner "shell" {
    script = "scripts/system_docker_setup.sh"
  }

  provisioner "shell" {
    script = "scripts/system_set_default_locale.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_cloudberry_motd.sh"
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
