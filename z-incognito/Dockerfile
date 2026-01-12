# Custom Neko Chromium with Intel VAAPI support for Raptor Lake
FROM ghcr.io/m1k1o/neko/intel-chromium:latest

# Add bookworm repos for newer Intel driver
RUN echo "deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware" >> /etc/apt/sources.list.d/bookworm.list && \
    echo "deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware" >> /etc/apt/sources.list.d/bookworm.list

# Install newer Intel media driver
RUN apt-get update && \
    apt-get install -y -t bookworm \
        intel-media-va-driver-non-free \
        libigdgmm12 \
        libva2 \
        libva-drm2 \
        libva-x11-2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Brave browser
RUN apt-get update && \
    apt-get install -y curl gnupg && \
    curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/brave-browser-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" > /etc/apt/sources.list.d/brave-browser-release.list && \
    apt-get update && \
    apt-get install -y brave-browser && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create Brave config directories with proper ownership
RUN mkdir -p /home/neko/.config/BraveSoftware/Brave-Browser/Crashpad && \
    chown -R neko:neko /home/neko/.config/BraveSoftware

# Create Brave supervisord config (replace chromium config)
RUN echo '[program:chromium]\n\
environment=HOME="/home/%(ENV_USER)s",USER="%(ENV_USER)s",DISPLAY="%(ENV_DISPLAY)s"\n\
command=/usr/bin/brave-browser\n\
  --window-position=0,0\n\
  --display=%(ENV_DISPLAY)s\n\
  --user-data-dir=/home/neko/.config/BraveSoftware/Brave-Browser\n\
  --no-first-run\n\
  --start-maximized\n\
  --force-dark-mode\n\
  --disable-dev-shm-usage\n\
  --no-sandbox\n\
  --password-store=basic\n\
stopsignal=INT\n\
autorestart=true\n\
priority=800\n\
user=%(ENV_USER)s\n\
stdout_logfile=/var/log/neko/chromium.log\n\
stdout_logfile_maxbytes=100MB\n\
stdout_logfile_backups=10\n\
redirect_stderr=true\n\
\n\
[program:openbox]\n\
environment=HOME="/home/%(ENV_USER)s",USER="%(ENV_USER)s",DISPLAY="%(ENV_DISPLAY)s"\n\
command=/usr/bin/openbox --config-file /etc/neko/openbox.xml\n\
autorestart=true\n\
priority=300\n\
user=%(ENV_USER)s\n\
stdout_logfile=/var/log/neko/openbox.log\n\
stdout_logfile_maxbytes=100MB\n\
stdout_logfile_backups=10\n\
redirect_stderr=true\n' > /etc/neko/supervisord/chromium.conf

# Set Intel iHD driver
ENV LIBVA_DRIVER_NAME=iHD
