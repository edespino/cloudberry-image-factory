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

source "amazon-ebs" "base-build-image" {
  access_key    = var.aws_access_key
  secret_key    = var.aws_secret_key
  token         = var.aws_session_token
  region        = var.region
  temporary_security_group_source_public_ip = true

  instance_type = "t3.2xlarge"

  source_ami_filter {
    filters = {
      name                = "*ubuntu-noble-24.04-amd64-minimal-*"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"]
    most_recent = true
  }

  ssh_username         = "ubuntu"

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

  # NOTE: system_configure_dnf.sh is RPM-only and intentionally omitted.
  # NOTE: The Rocky 10 kernel-modules-extra upgrade + reboot is also omitted:
  # Ubuntu AWS kernels ship xt_addrtype/br_netfilter in the default
  # linux-modules-*-aws package, so Docker needs no kernel work here.

  provisioner "shell" {
    script = "scripts/system_add_synxdb_cloud_dependencies.sh"
  }

  # Configure en_US.UTF-8 system locale (DEB platforms only)
  provisioner "shell" {
    script = "scripts/system_set_default_locale.sh"
  }

  # NOTE: The rocky10-synxdb-cloud "upgrade system pip" step (ensurepip) is
  # omitted: ensurepip is disabled on Debian/Ubuntu and the system Python is
  # PEP 668 externally managed. python3-pip/python3-venv come from apt via
  # system_add_synxdb_cloud_dependencies.sh; venvs upgrade their own pip below.

  # Install Python dependencies in venv (omnistrate-cli-tools + synxdb-cli)
  provisioner "shell" {
    inline = [
      "python3 -m venv /home/ubuntu/.venv",
      "/home/ubuntu/.venv/bin/pip install --upgrade pip",
      "/home/ubuntu/.venv/bin/pip install 'rich>=13.0.0' 'click>=8.0.0' 'pyyaml>=6.0.0' 'pydantic>=2.0.0' 'pydantic-settings>=2.0.0' 'boto3>=1.28.0' 'readchar>=4.0.0' 'typer>=0.9.0' 'httpx>=0.25.0' check-jsonschema"
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
    script = "../../../../common/scripts/system_add_azure_cli.sh"
  }

  provisioner "shell" {
    script = "../../../../common/scripts/system_add_gcloud_cli.sh"
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

  # Configure ubuntu environment
  provisioner "shell" {
    script = "../../../../common/scripts/dbadmin_configure_environment.sh"
    environment_vars = [
      "DB_USERNAME=ubuntu"
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
    script = "../../../../common/scripts/system_add_k9s.sh"
  }

  # Install kind (Kubernetes IN Docker)
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_kind.sh"
  }

  # Install Terraform
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_terraform.sh"
  }

  # Install OpenTofu
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_tofu.sh"
  }

  # Install Packer (HashiCorp APT repo)
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_packer.sh"
  }

  # Install age (file encryption)
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_age.sh"
  }

  # Install sops (secrets management)
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_sops.sh"
  }

  # Install ansible-core + community.sops collection
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_ansible.sh"
  }

  # Install uv (general Python tooling)
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_uv.sh"
  }

  # Install Node.js 22 LTS (general JS tooling; npm-installed CLIs)
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_nodejs.sh"
  }

  provisioner "shell" {
    script = "../../../../common/scripts/system_add_1password_cli.sh"
  }

  provisioner "shell" {
    script = "../../../../common/scripts/system_add_direnv.sh"
  }

  provisioner "shell" {
    script = "../../../../common/scripts/system_add_motd_manager.sh"
    environment_vars = [
      "MOTD_TEMPLATE=synx"
    ]
  }

  # Install gitleaks + auto-enable pre-commit hook via init.templatedir
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_gitleaks.sh"
  }

  # Install Cloudsmith CLI via uv tool (isolated venv; works under access-env PYTHONNOUSERSITE=1)
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_cloudsmith_cli.sh"
  }

  # Install autoenv for .env file support (system-wide)
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_autoenv.sh"
  }

  # Install git-profile selector command
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_git_profiles.sh"
  }

  # Install zellij terminal multiplexer
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_zellij.sh"
  }

  # Install hwatch (modern watch alternative)
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_hwatch.sh"
  }

  # Install dysk (better df alternative)
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_dysk.sh"
  }

  # Install zoxide (smarter cd command)
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_zoxide.sh"
  }

  # Install Go
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_golang.sh"
  }

  # Install Dolt
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_dolt.sh"
  }

  # Install Bun JavaScript runtime
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_bun.sh"
  }

  # Configure SSH agent forwarding persistence for tmux
  provisioner "shell" {
    script = "../../../../common/scripts/system_configure_ssh_agent_tmux.sh"
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
