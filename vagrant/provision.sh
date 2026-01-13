#!/bin/bash
# Extra provisioning helper (optional). This is kept for convenience if you want to do more complex tasks.
set -e

# Example: install some debugging tools
sudo dnf -y install net-tools iproute vim wget curl jq || true
