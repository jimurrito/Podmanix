#!/usr/bin/env bash
# 

echo "Starting Podman Container(s)"
systemctl start "${1}.service"
echo "Started ${1}.service"
