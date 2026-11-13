#!/bin/sh
# Install the Slate skin after the image has populated its application directory.
# The source is mounted read-only at /opt/slate; the copy replaces any older version.
set -eu
rm -rf /var/www/html/skins/slate.new
cp -R /opt/slate /var/www/html/skins/slate.new
rm -rf /var/www/html/skins/slate
mv /var/www/html/skins/slate.new /var/www/html/skins/slate
