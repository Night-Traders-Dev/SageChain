#!/bin/bash
# Orbit Blockchain - Installation Script
# Run as root: sudo ./install.sh

set -euo pipefail

ORBIT_USER="orbit"
ORBIT_GROUP="orbit"
ORBIT_HOME="/opt/orbit"
ORBIT_CONFIG="/etc/orbit/config.toml"
SAGE_BIN="/usr/local/bin/sage-c"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

install_sage() {
    log_info "Installing Sage runtime..."
    if command -v sage-c &> /dev/null; then
        log_info "sage-c already installed: $(sage-c --version)"
        return 0
    fi

    # Download and install Sage (placeholder - actual install depends on distribution)
    log_warn "Sage installation not implemented - please install Sage manually"
    log_warn "Visit: https://github.com/sage-lang/sage"
    return 1
}

create_user() {
    log_info "Creating orbit user..."
    if id "$ORBIT_USER" &>/dev/null; then
        log_info "User $ORBIT_USER already exists"
    else
        useradd -r -s /bin/false -d "$ORBIT_HOME" -c "Orbit Blockchain" "$ORBIT_USER"
        log_info "Created user $ORBIT_USER"
    fi
}

create_directories() {
    log_info "Creating directories..."
    mkdir -p "$ORBIT_HOME"/{data,logs,config}
    mkdir -p /etc/orbit
    mkdir -p /var/log/orbit
    chown -R "$ORBIT_USER:$ORBIT_GROUP" "$ORBIT_HOME" /var/log/orbit
    chmod 750 "$ORBIT_HOME" "$ORBIT_HOME"/data "$ORBIT_HOME"/logs
    chmod 755 /etc/orbit
}

install_config() {
    log_info "Installing config..."
    if [[ -f "$ORBIT_CONFIG" ]]; then
        log_warn "Config already exists at $ORBIT_CONFIG, backing up..."
        cp "$ORBIT_CONFIG" "$ORBIT_CONFIG.backup.$(date +%s)"
    fi
    cp deploy/config.toml "$ORBIT_CONFIG"
    chown "$ORBIT_USER:$ORBIT_GROUP" "$ORBIT_CONFIG"
    chmod 640 "$ORBIT_CONFIG"
    log_info "Config installed to $ORBIT_CONFIG"
}

install_binaries() {
    log_info "Installing binaries..."
    # In production, these would be compiled binaries
    # For now, create wrapper scripts that call sage-c
    cat > /usr/local/bin/orbit-node << 'EOF'
#!/bin/bash
exec sage-c /opt/orbit/orbit/node/main.sage --config /etc/orbit/config.toml "$@"
EOF
    chmod +x /usr/local/bin/orbit-node

    cat > /usr/local/bin/orbit-miner << 'EOF'
#!/bin/bash
exec sage-c /opt/orbit/orbit/mining/miner.sage --config /etc/orbit/config.toml "$@"
EOF
    chmod +x /usr/local/bin/orbit-miner

    cat > /usr/local/bin/orbit-rpc << 'EOF'
#!/bin/bash
exec sage-c /opt/orbit/orbit/api/rpc_server.sage --config /etc/orbit/config.toml "$@"
EOF
    chmod +x /usr/local/bin/orbit-rpc

    cat > /usr/local/bin/orbit-explorer << 'EOF'
#!/bin/bash
exec sage-c /opt/orbit/orbit/api/explorer_server.sage --config /etc/orbit/config.toml "$@"
EOF
    chmod +x /usr/local/bin/orbit-explorer

    cat > /usr/local/bin/orbin << 'EOF'
#!/bin/bash
exec sage-c /opt/orbit/orbit/cli/orbin.sage "$@"
EOF
    chmod +x /usr/local/bin/orbin
}

install_systemd() {
    log_info "Installing systemd services..."
    cp deploy/systemd/*.service /etc/systemd/system/
    cp deploy/systemd/orbit.target /etc/systemd/system/
    systemctl daemon-reload
    log_info "Systemd services installed"
}

setup_logging() {
    log_info "Setting up log rotation..."
    cat > /etc/logrotate.d/orbit << 'EOF'
/opt/orbit/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0640 orbit orbit
    sharedscripts
    postrotate
        systemctl reload orbit-node > /dev/null 2>&1 || true
    endscript
}
EOF
    log_info "Log rotation configured"
}

setup_firewall() {
    log_info "Configuring firewall (ufw)..."
    if command -v ufw &> /dev/null; then
        ufw allow 8333/tcp comment "Orbit P2P"
        ufw allow 8545/tcp comment "Orbit RPC" 2>/dev/null || true
        ufw allow 3000/tcp comment "Orbit Explorer" 2>/dev/null || true
        ufw allow 9090/tcp comment "Orbit Metrics" 2>/dev/null || true
        log_info "Firewall rules added"
    else
        log_warn "ufw not installed, skipping firewall config"
    fi
}

main() {
    log_info "Starting Orbit Blockchain installation..."
    check_root
    install_sage
    create_user
    create_directories
    install_config
    install_binaries
    install_systemd
    setup_logging
    setup_firewall

    log_info "Installation complete!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Edit $ORBIT_CONFIG to customize settings"
    log_info "  2. Start services: systemctl start orbit.target"
    log_info "  3. Enable on boot: systemctl enable orbit.target"
    log_info "  4. Check status: systemctl status orbit.target"
    log_info "  5. View logs: journalctl -u orbit-node -f"
}

main "$@"