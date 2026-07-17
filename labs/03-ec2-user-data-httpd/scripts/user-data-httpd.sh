#!/bin/bash
# EC2 user data for Amazon Linux 2023.
# Installs Apache, publishes a simple page, and enables the service at boot.

set -euo pipefail

dnf install -y httpd
printf '%s\n' 'Provisioned by EC2 user data' > /var/www/html/index.html
systemctl enable --now httpd
