#!/bin/bash
# Orbit Blockchain - Service Management Script
# Usage: orbit-ctl {start|stop|restart|status|logs} [service]

set -euo pipefail

SERVICES=("orbit-node" "orbit-miner" "orbit-rpc" "orbit-explorer")

usage() {
    echo "Usage: $0 {start|stop|restart|status|logs|enable|disable} [service]"
    echo "Services: ${SERVICES[*]}"
    echo "If no service specified, operates on all services via orbit.target"
    exit 1
}

service_action() {
    local action=$1
    local service=$2

    if [[ -n "$service" ]]; then
        if [[ ! " ${SERVICES[*]} " =~ " ${service} " ]]; then
            echo "Unknown service: $service"
            exit 1
        fi
        systemctl "$action" "$service"
    else
        systemctl "$action" orbit.target
    fi
}

case "${1:-}" in
    start)
        service_action start "${2:-}"
        ;;
    stop)
        service_action stop "${2:-}"
        ;;
    restart)
        service_action restart "${2:-}"
        ;;
    status)
        if [[ -n "${2:-}" ]]; then
            systemctl status "${2}"
        else
            systemctl status orbit.target
            echo ""
            for svc in "${SERVICES[@]}"; do
                echo "--- $svc ---"
                systemctl is-active "$svc" 2>/dev/null || echo "inactive"
            done
        fi
        ;;
    logs)
        if [[ -n "${2:-}" ]]; then
            journalctl -u "${2}" -f
        else
            journalctl -u orbit-node -u orbit-miner -u orbit-rpc -u orbit-explorer -f
        fi
        ;;
    enable)
        service_action enable "${2:-}"
        ;;
    disable)
        service_action disable "${2:-}"
        ;;
    *)
        usage
        ;;
esac