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

# Chained target: the source AMI is the newest tested image of another target
# in this account (see CLAUDE.md, "Chained from agentic/ubuntu26").
variable "base_family" {
  type    = string
  default = "agentic"
}

variable "base_os" {
  type    = string
  default = "ubuntu26"
}

source "amazon-ebs" "gpu-build-image" {
  access_key    = var.aws_access_key
  secret_key    = var.aws_secret_key
  token         = var.aws_session_token
  region        = var.region
  temporary_security_group_source_public_ip = true

  # A real L4 so the build-time GPU smoke test exercises the driver and
  # Ollama's CUDA path. Not t3.*: the goss test instance (t3.medium) has no
  # GPU, so GPU verification can only happen here.
  instance_type = "g6.xlarge"

  # packer-build-and-test.sh records PASSED/FAILED on the AMI's Name *tag*
  # (the AMI name attribute is never renamed), so the chain filters on
  # tag:Name. The "-2*" segment keeps ubuntu26-arm64-* and ubuntu26-gpu-*
  # images out of the candidate set; architecture is a second guard.
  source_ami_filter {
    filters = {
      "tag:Name"          = "${var.base_family}-packer-${var.base_os}-2*-PASSED"
      architecture        = "x86_64"
      virtualization-type = "hvm"
    }
    owners      = ["self"]
    most_recent = true
  }

  ssh_username         = "ubuntu"

  # Omit ami_description: it would call denied ModifyImageAttribute.
  ami_name = format("%s-packer-%s-%s", var.family, var.os_name, formatdate("YYYYMMDD-HHmmss", timestamp()))

  # Base is 24 GiB; the driver stack and Ollama runtime need headroom.
  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 32
    volume_type           = "gp3"
    delete_on_termination = true
  }
}

build {
  sources = ["source.amazon-ebs.gpu-build-image"]

  # NOTE: Every base provisioner (OS packages, users, cloud/dev tooling, the
  # AI toolchain, docker) already ran in the agentic/ubuntu26 image this
  # build chains from. Do not re-run them here; this template layers only the
  # GPU stack.

  # NVIDIA server driver for the linux-aws kernel (prebuilt signed modules,
  # no DKMS) + nvidia-utils (nvidia-smi); all three packages apt-mark held.
  # NVIDIA_BRANCH must match the package names asserted in tests/goss.yaml.
  provisioner "shell" {
    script = "scripts/system_add_nvidia_driver.sh"
    environment_vars = [
      "NVIDIA_BRANCH=580"
    ]
  }

  # Reboot so nouveau (blacklisted by the driver packages) unloads and the
  # nvidia module loads; also brings up any kernel the base upgraded into.
  provisioner "shell" {
    inline            = ["sudo reboot"]
    expect_disconnect = true
  }

  # GPU process monitor (Ubuntu universe)
  provisioner "shell" {
    pause_before = "30s"
    script       = "scripts/system_add_nvtop.sh"
  }

  # Ollama inference server: latest GitHub release (OLLAMA_VERSION pins),
  # systemd service as user ollama, loopback-only (OLLAMA_HOST is never set),
  # no model weights.
  provisioner "shell" {
    script = "scripts/system_add_ollama.sh"
  }

  # Build-time GPU smoke test on the g6.xlarge builder: nvidia module loaded,
  # nouveau absent, nvidia-smi reports the L4, ollama active with a CUDA
  # accelerator, port 11434 bound to 127.0.0.1 only. Fails the build on any
  # miss. These checks cannot live in goss (GPU-less test instance).
  provisioner "shell" {
    script = "scripts/system_verify_gpu_stack.sh"
  }

  # goss is already on the base image (the script is a no-op when present);
  # kept so this template, like every target, ends with the test framework.
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_goss.sh"
  }

  post-processors {
    post-processor "manifest" {
      output = "packer-manifest.json"
    }
  }
}
