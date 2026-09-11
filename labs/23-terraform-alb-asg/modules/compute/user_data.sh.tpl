#!/bin/bash
set -euo pipefail

dnf install -y httpd
systemctl enable --now httpd

cat > /var/www/html/health <<'HEALTH'
OK
HEALTH

IMDS_TOKEN="$(curl -sS --fail --max-time 2 \
  -X PUT \
  -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600' \
  http://169.254.169.254/latest/api/token)"

INSTANCE_ID="$(curl -sS --fail --max-time 2 \
  -H "X-aws-ec2-metadata-token: $${IMDS_TOKEN}" \
  http://169.254.169.254/latest/meta-data/instance-id)"

AVAILABILITY_ZONE="$(curl -sS --fail --max-time 2 \
  -H "X-aws-ec2-metadata-token: $${IMDS_TOKEN}" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)"

cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html>
<head>
  <title>${project_name} - Terraform Infrastructure</title>
</head>
<body>
  <h1>Hello from Terraform Infrastructure!</h1>
  <p><strong>Project:</strong> ${project_name}</p>
  <p><strong>Instance ID:</strong> $${INSTANCE_ID}</p>
  <p><strong>Availability Zone:</strong> $${AVAILABILITY_ZONE}</p>
</body>
</html>
HTML

chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html
