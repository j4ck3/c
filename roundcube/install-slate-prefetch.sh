#!/bin/sh
# Install the Slate prefetch plugin after the image has populated its application directory.
set -eu
install -d -m 0755 /var/www/html/plugins/slate_prefetch
install -m 0644 /opt/slate_prefetch/slate_prefetch.php /var/www/html/plugins/slate_prefetch/slate_prefetch.php
