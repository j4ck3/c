#!/bin/sh
# Install the local logging hook after the image has populated its application directory.
set -eu
install -d -m 0755 /var/www/html/plugins/private_log_redaction
install -m 0644 /opt/private_log_redaction/private_log_redaction.php /var/www/html/plugins/private_log_redaction/private_log_redaction.php
