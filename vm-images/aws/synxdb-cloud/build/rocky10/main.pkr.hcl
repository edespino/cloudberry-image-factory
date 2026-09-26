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
  # Rocky AMIs lack the SSM agent; the user data below installs and starts it
  # at first boot. Packer does not retry the session, so it waits for that
  # install (the agent registered ~45 s after launch on Rocky 10 in testing).
  pause_before_ssm            = "2m"
  user_data_file              = "../../../../common/cloud-init/ssm-agent-rpm.yaml"
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
      name                = "Rocky-10-EC2-Base-10.*-*.*.x86_64"
      virtualization-type = "hvm"
    }
    owners      = ["792107900819"]
    most_recent = true
  }

  ssh_username         = "rocky"
  # Remove Packer's temporary public key from authorized_keys before capture.
  ssh_clear_authorized_keys = true

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

  # Configure rocky environment
  provisioner "shell" {
    script = "../../../../common/scripts/dbadmin_configure_environment.sh"
    environment_vars = [
      "DB_USERNAME=rocky"
    ]
  }

  provisioner "shell" {
    script = "../../../../common/scripts/system_add_gh.sh"
  }

  # Install glow (terminal markdown viewer, Charm repo)
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_glow.sh"
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

  # Install Packer (HashiCorp RPM repo)
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

  # Install Emacs (built from source)
  provisioner "shell" {
    script = "../../../../common/scripts/system_add_emacs.sh"
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
