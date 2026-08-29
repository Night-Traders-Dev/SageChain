#!/bin/bash
# Orbit Blockchain - Backup Script
# Run via cron for regular backups

set -euo pipefail

DATA_DIR="/opt/orbit/data"
BACKUP_DIR="/opt/orbit/backups"
RETENTION_DAYS=30
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

backup_chain() {
    log "Backing up chain data..."
    tar -czf "$BACKUP_DIR/chain_$DATE.tar.gz" -C "$DATA_DIR" chain.json 2>/dev/null || true
}

backup_genesis() {
    log "Backing up genesis..."
    tar -czf "$BACKUP_DIR/genesis_$DATE.tar.gz" -C "$DATA_DIR" genesis.json 2>/dev/null || true
}

backup_keystores() {
    log "Backing up keystores..."
    tar -czf "$BACKUP_DIR/keystores_$DATE.tar.gz" \
        -C "$DATA_DIR" wallet_keystore.json validator_keystore.json 2>/dev/null || true
}

backup_config() {
    log "Backing up config..."
    tar -czf "$BACKUP_DIR/config_$DATE.tar.gz" /etc/orbit/config.toml 2>/dev/null || true
}

cleanup_old_backups() {
    log "Cleaning up backups older than $RETENTION_DAYS days..."
    find "$BACKUP_DIR" -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete
}

main() {
    log "Starting backup..."
    backup_chain
    backup_genesis
    backup_keystores
    backup_config
    cleanup_old_backups
    log "Backup complete. Files in $BACKUP_DIR:"
    ls -lh "$BACKUP_DIR"
}

main "$@"