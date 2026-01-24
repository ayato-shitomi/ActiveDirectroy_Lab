#!/bin/bash
# Bastion Host Setup Script
# This script is executed by EC2 user_data on first boot

set -e

LOG_FILE="/var/log/bastion-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "Bastion Host Setup - $(date)"
echo "=========================================="

# Update system packages
echo "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install useful tools
echo "Installing tools..."
apt-get install -y \
    net-tools \
    dnsutils \
    nmap \
    htop \
    vim \
    tmux \
    curl \
    wget \
    jq \
    python3-pip

# Install xfreerdp if available (may not be on minimal installs)
apt-get install -y freerdp2-x11 || echo "freerdp2-x11 not available"

# Install AWS CLI
echo "Installing AWS CLI..."
if ! command -v aws &> /dev/null; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    cd /tmp
    unzip -q awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
fi

# Configure SSH
echo "Configuring SSH..."
cat >> /etc/ssh/sshd_config << 'EOF'

# AD Lab Bastion Configuration
GatewayPorts yes
AllowTcpForwarding yes
EOF

systemctl restart ssh

# Create helper scripts directory
mkdir -p /opt/adlab/scripts

# Create RDP connection helper script
cat > /opt/adlab/scripts/rdp-connect.sh << 'SCRIPT'
#!/bin/bash
# RDP Connection Helper Script

usage() {
    echo "Usage: $0 <target_ip> [local_port]"
    echo "Example: $0 10.100.1.10 3389"
    exit 1
}

if [ -z "$1" ]; then
    usage
fi

TARGET_IP="$1"
LOCAL_PORT="$${2:-3389}"

echo "Starting RDP session to $TARGET_IP"
echo "Use: xfreerdp /v:$TARGET_IP /u:Administrator"

xfreerdp /v:$TARGET_IP /u:Administrator /cert-ignore /dynamic-resolution
SCRIPT
chmod +x /opt/adlab/scripts/rdp-connect.sh

# Create pod information display script
POD_COUNT=${pod_count}
cat > /opt/adlab/scripts/show-pods.sh << SCRIPT
#!/bin/bash
# Display Pod Information

echo "=========================================="
echo "AD Lab Pod Information"
echo "=========================================="
echo ""
echo "Pod Count: $POD_COUNT"
echo ""
echo "Network Layout:"
echo "  VPC CIDR: 10.100.0.0/16"
echo "  Public Subnet: 10.100.0.0/24 (Bastion)"
echo ""

for i in \$(seq 1 $POD_COUNT); do
    echo "Pod \$i (Subnet: 10.100.\$i.0/24):"
    echo "  DC:      10.100.\$i.10 (Domain Controller)"
    echo "  FILESRV: 10.100.\$i.20 (File Server)"
    echo "  CLIENT:  10.100.\$i.30 (Client)"
    echo ""
done

echo "=========================================="
echo "Connection Examples:"
echo "=========================================="
echo ""
echo "SSH Tunnel for RDP (run on your local machine):"
echo "  ssh -L 3389:10.100.1.10:3389 ubuntu@<bastion-ip>"
echo ""
echo "Then connect via RDP to: localhost:3389"
echo ""
echo "Domain Credentials:"
echo "  Domain: LAB"
echo "  Users: tanaka, hasegawa, saitou"
echo "  Password: P@ssw0rd!"
echo ""
echo "File Shares:"
echo "  \\\\\\\\FILESRV1\\\\Share"
echo "  \\\\\\\\FILESRV1\\\\Public"
echo "  \\\\\\\\FILESRV1\\\\<username>"
echo "=========================================="
SCRIPT
chmod +x /opt/adlab/scripts/show-pods.sh

# Add scripts to PATH
echo 'export PATH=$PATH:/opt/adlab/scripts' >> /etc/profile.d/adlab.sh

# Create MOTD
cat > /etc/motd << 'MOTD'

==========================================
   AD Lab Bastion Host
==========================================

Useful Commands:
  show-pods.sh    - Display pod information
  rdp-connect.sh  - Connect to Windows host via RDP

SSH Tunneling Example:
  ssh -L 3389:10.100.1.30:3389 ubuntu@localhost

Then RDP to localhost:3389

==========================================

MOTD

echo "=========================================="
echo "Bastion setup completed successfully!"
echo "=========================================="
