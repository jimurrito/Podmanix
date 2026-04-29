#!/usr/bin/env bash
# 

echo "Stopping Podman Container(s)"
systemctl stop "${1}.service"
echo "Stopped ${1}.service"
