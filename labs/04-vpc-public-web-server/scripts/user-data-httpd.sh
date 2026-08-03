#!/bin/bash
# First-boot user data for an Amazon Linux 2 EC2 instance.
# Installs Apache and serves a simple static page.
#
# Usage: paste this into the EC2 "User data" field at launch,
# or run it manually on the instance for testing.
set -euo pipefail

yum install -y httpd

cat > /var/www/html/index.html <<'EOF'
<html>
<head><title>My VPC web server</title></head>
<body>
<h1>Hello from a public subnet</h1>
<p>This page is served by Apache on an EC2 instance inside a VPC.</p>
</body>
</html>
EOF

systemctl enable httpd
systemctl start httpd
