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

variable "cloudsmith_user" {
  type      = string
  sensitive = true
}

variable "cloudsmith_token" {
  type      = string
  sensitive = true
}

source "amazon-ebs" "base-build-image" {
  access_key    = var.aws_access_key
  secret_key    = var.aws_secret_key
  token         = var.aws_session_token
  region        = var.region

  instance_type = "t3.2xlarge"

  source_ami_filter {
    filters = {
      name                = "Rocky-10-EC2-Base-10.*-*.*.x86_64"
      virtualization-type = "hvm"
    }
    owners      = ["792107900819"]
    most_recent = true
  }

  ssh_username         = "rocky"

  ami_name = format("synxdb-cloud-packer-%s-%s-%s", var.vm_type, var.os_name, formatdate("YYYYMMDD-HHmmss", timestamp()))
  ami_description = "SynxDB Cloud - Rocky Linux 10 Base AMI built via Packer"

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
    script = "../common/scripts/system_configure_dnf.sh"
  }

  provisioner "shell" {
    script = "scripts/system_add_synxdb_cloud_dependencies.sh"
  }

  # Reboot into the upgraded kernel so kernel-modules-extra matches uname -r
  # (required for Docker's xt_addrtype/br_netfilter modprobe later in the bake)
  provisioner "shell" {
    inline            = ["sudo reboot"]
    expect_disconnect = true
  }

  provisioner "shell" {
    pause_before = "30s"
    inline = [
      "echo 'Back online after kernel upgrade, running kernel:'",
      "uname -r"
    ]
  }

  # Upgrade system pip so new venvs created with --upgrade-deps get a current version
  provisioner "shell" {
    inline = [
      "sudo python3 -m ensurepip --upgrade",
      "sudo python3 -m pip install --upgrade pip"
    ]
  }

  # Install Python dependencies in venv (omnistrate-cli-tools + synxdb-cli)
  provisioner "shell" {
    inline = [
      "python3 -m venv /home/rocky/.venv",
      "/home/rocky/.venv/bin/pip install --upgrade pip",
      "/home/rocky/.venv/bin/pip install 'rich>=13.0.0' 'click>=8.0.0' 'pyyaml>=6.0.0' 'pydantic>=2.0.0' 'pydantic-settings>=2.0.0' 'boto3>=1.28.0' 'readchar>=4.0.0' 'typer>=0.9.0' 'httpx>=0.25.0' check-jsonschema"
    ]
  }

  # Create gpadmin user first
  provisioner "shell" {
    script = "../common/scripts/system_adduser_dbadmin.sh"
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
    script = "../common/scripts/system_add_yq.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_awscli.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_azure_cli.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_gcloud_cli.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_set_timezone.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_config_starship_prompt.sh"
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

  # Configure rocky environment
  provisioner "shell" {
    script = "../common/scripts/dbadmin_configure_environment.sh"
    environment_vars = [
      "DB_USERNAME=rocky"
    ]
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_gh.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_helm_kubectl.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_omnistrate_ctl.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_k9s.sh"
  }

  # Install kind (Kubernetes IN Docker)
  provisioner "shell" {
    script = "../common/scripts/system_add_kind.sh"
  }

  # Install Terraform
  provisioner "shell" {
    script = "../common/scripts/system_add_terraform.sh"
  }

  # Install OpenTofu
  provisioner "shell" {
    script = "../common/scripts/system_add_tofu.sh"
  }

  # Install Packer (HashiCorp RPM repo)
  provisioner "shell" {
    script = "../common/scripts/system_add_packer.sh"
  }

  # Install age (file encryption)
  provisioner "shell" {
    script = "../common/scripts/system_add_age.sh"
  }

  # Install sops (secrets management)
  provisioner "shell" {
    script = "../common/scripts/system_add_sops.sh"
  }

  # Install ansible-core + community.sops collection
  provisioner "shell" {
    script = "../common/scripts/system_add_ansible.sh"
  }

  # Install uv (required by omnigent)
  provisioner "shell" {
    script = "../common/scripts/system_add_uv.sh"
  }

  # Install Node.js 22 LTS (required by omnigent's claude/codex/pi harnesses)
  provisioner "shell" {
    script = "../common/scripts/system_add_nodejs.sh"
  }

  # Install PI coding agent (pi) for rocky (per-user so `pi update` works)
  provisioner "shell" {
    script = "../common/scripts/system_add_pi.sh"
    environment_vars = [
      "DB_USERNAME=rocky"
    ]
  }

  # Install Omnigent for rocky
  provisioner "shell" {
    script = "../common/scripts/system_add_omnigent.sh"
    environment_vars = [
      "DB_USERNAME=rocky"
    ]
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_1password_cli.sh"
  }

  provisioner "shell" {
    script = "../common/scripts/system_add_direnv.sh"
  }

  # # Install SynxDB DBaaS package (disabled)
  # provisioner "shell" {
  #   script = "../common/scripts/system_add_synxdb_dbaas.sh"
  #   environment_vars = [
  #     "CLOUDSMITH_USER=${var.cloudsmith_user}",
  #     "CLOUDSMITH_TOKEN=${var.cloudsmith_token}",
  #     "INSTALL_USER=cbadmin"
  #   ]
  # }

  provisioner "shell" {
    script = "../common/scripts/system_add_motd_manager.sh"
    environment_vars = [
      "MOTD_TEMPLATE=synx"
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

  # Install Claude CLI for rocky
  provisioner "shell" {
    script = "../common/scripts/system_add_claude.sh"
    environment_vars = [
      "DB_USERNAME=rocky"
    ]
  }

  # Install gitleaks + auto-enable pre-commit hook via init.templatedir
  provisioner "shell" {
    script = "../common/scripts/system_add_gitleaks.sh"
  }

  # Install OpenCode CLI (installs for rocky, the Packer SSH user)
  provisioner "shell" {
    script = "../common/scripts/system_add_opencode.sh"
  }

  # Install Cloudsmith CLI (pip --user, installs to /home/rocky/.local/bin/cloudsmith)
  provisioner "shell" {
    script = "../common/scripts/system_add_cloudsmith_cli.sh"
  }

  # Install autoenv for .env file support (system-wide)
  provisioner "shell" {
    script = "../common/scripts/system_add_autoenv.sh"
  }

  # Install git-profile selector command
  provisioner "shell" {
    script = "../common/scripts/system_add_git_profiles.sh"
  }

  # Install zellij terminal multiplexer
  provisioner "shell" {
    script = "../common/scripts/system_add_zellij.sh"
  }

  # Install hwatch (modern watch alternative)
  provisioner "shell" {
    script = "../common/scripts/system_add_hwatch.sh"
  }

  # Install dysk (better df alternative)
  provisioner "shell" {
    script = "../common/scripts/system_add_dysk.sh"
  }

  # Install zoxide (smarter cd command)
  provisioner "shell" {
    script = "../common/scripts/system_add_zoxide.sh"
  }

  # Install Go (required for gastown)
  provisioner "shell" {
    script = "../common/scripts/system_add_golang.sh"
  }

  # Install Dolt (required for gastown)
  provisioner "shell" {
    script = "../common/scripts/system_add_dolt.sh"
  }

  # Install beads/bd (required for gastown)
  provisioner "shell" {
    script = "../common/scripts/system_add_beads.sh"
  }

  # Install Bun JavaScript runtime
  provisioner "shell" {
    script = "../common/scripts/system_add_bun.sh"
  }

  # Install gastown (gt) multi-agent workspace manager
  provisioner "shell" {
    script = "../common/scripts/system_add_gastown.sh"
  }

  # Install Emacs (built from source)
  provisioner "shell" {
    script = "../common/scripts/system_add_emacs.sh"
  }

  # Configure SSH agent forwarding persistence for tmux
  provisioner "shell" {
    script = "../common/scripts/system_configure_ssh_agent_tmux.sh"
  }

  # Configure Claude Code settings for gpadmin
  provisioner "shell" {
    script = "../common/scripts/system_configure_claude.sh"
    environment_vars = [
      "DB_USERNAME=gpadmin"
    ]
  }

  # Configure Claude Code settings for cbadmin
  provisioner "shell" {
    script = "../common/scripts/system_configure_claude.sh"
    environment_vars = [
      "DB_USERNAME=cbadmin"
    ]
  }

  # Configure Claude Code settings for rocky
  provisioner "shell" {
    script = "../common/scripts/system_configure_claude.sh"
    environment_vars = [
      "DB_USERNAME=rocky"
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
