#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_kernel_configs.sh..."

# Create the sysctl configuration file for database settings
cat <<'EOF' | sudo tee /etc/sysctl.d/90-db-sysctl.conf
# /etc/sysctl.d/90-db-sysctl.conf

# Maximum size of a single message (in bytes)
kernel.msgmax = 65536

# Maximum size of a message queue (in bytes)
kernel.msgmnb = 65536

# Maximum number of message queue identifiers
kernel.msgmni = 2048

# Semaphore settings: semmsl, semmns, semopm, semmni
kernel.sem = 500 2048000 200 8192

# Maximum number of shared memory segments
kernel.shmmni = 1024

# Append PID to core filenames
kernel.core_uses_pid = 1

# Pattern for core dump file names
kernel.core_pattern = /var/crash/core-%e-%s-%u-%g-%p-%t

# Enable SysRq key (1 to enable, 0 to disable)
kernel.sysrq = 1

# Maximum number of packets in the network device queue
net.core.netdev_max_backlog = 2000

# Maximum receive socket buffer size (in bytes)
net.core.rmem_max = 4194304

# Maximum send socket buffer size (in bytes)
net.core.wmem_max = 4194304

# Default receive socket buffer size (in bytes)
net.core.rmem_default = 4194304

# Default send socket buffer size (in bytes)
net.core.wmem_default = 4194304

# TCP read buffer sizes: min, default, max (in bytes)
net.ipv4.tcp_rmem = 4096 4224000 16777216

# TCP write buffer sizes: min, default, max (in bytes)
net.ipv4.tcp_wmem = 4096 4224000 16777216

# Maximum amount of option memory buffers (in bytes)
net.core.optmem_max = 4194304

# Maximum number of incoming connections
net.core.somaxconn = 10000

# Enable or disable IP forwarding (1 to enable, 0 to disable)
net.ipv4.ip_forward = 0

# TCP congestion control algorithm
net.ipv4.tcp_congestion_control = cubic

# Default queue discipline
net.core.default_qdisc = fq_codel

# Enable or disable TCP MTU probing (1 to enable, 0 to disable)
net.ipv4.tcp_mtu_probing = 0

# Enable ARP filtering
net.ipv4.conf.all.arp_filter = 1

# Disable source routing by default
net.ipv4.conf.default.accept_source_route = 0

# Local port range for outgoing connections
net.ipv4.ip_local_port_range = 10000 65535

# Maximum number of remembered connection requests, which still did not receive an acknowledgment from connecting client
net.ipv4.tcp_max_syn_backlog = 4096

# Enable TCP SYN cookies
net.ipv4.tcp_syncookies = 1

# High threshold for IP fragment storage (in bytes)
net.ipv4.ipfrag_high_thresh = 41943040

# Low threshold for IP fragment storage (in bytes)
net.ipv4.ipfrag_low_thresh = 31457280

# Time to keep an IP fragment in memory (in seconds)
net.ipv4.ipfrag_time = 60

# Reserved ports for special use
net.ipv4.ip_local_reserved_ports = 65330

# Virtual memory settings
# Overcommit memory mode (2: Don't overcommit)
vm.overcommit_memory = 2

# Overcommit memory ratio
vm.overcommit_ratio = 95

# Swappiness (tendency to swap to disk)
vm.swappiness = 10

# Dirty page expiration time (in centiseconds)
vm.dirty_expire_centisecs = 500

# Interval between background writebacks of dirty pages (in centiseconds)
vm.dirty_writeback_centisecs = 100

# Disable zone reclaim mode
vm.zone_reclaim_mode = 0
EOF

# Apply the sysctl settings
sudo sysctl -p /etc/sysctl.d/90-db-sysctl.conf

sudo mkdir -p /var/crash/
sudo chmod 1777 /var/crash/

# Footer indicating the script execution is complete
echo "system_add_kernel_configs.sh execution completed."
