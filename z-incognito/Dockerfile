# Custom Neko Chromium with Intel VAAPI support and fingerprint hardening
FROM ghcr.io/m1k1o/neko/intel-chromium:latest

# Clear stale X lock/socket at startup so x-server can start after container restarts
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# Add bookworm repos for newer Intel drivers
RUN echo "deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware" >> /etc/apt/sources.list.d/bookworm.list && \
    echo "deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware" >> /etc/apt/sources.list.d/bookworm.list

# Install Intel GPU drivers:
#  - VAAPI drivers for hardware video encoding
#  - Mesa OpenGL/Vulkan drivers for WebGL (fixes SwiftShader fallback)
RUN apt-get update && \
    apt-get install -y -t bookworm \
        intel-media-va-driver-non-free \
        libigdgmm12 \
        libva2 \
        libva-drm2 \
        libva-x11-2 \
        libgl1-mesa-dri \
        mesa-vulkan-drivers \
        libegl-mesa0 \
        libgbm1 \
        libglx-mesa0 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Remove uncommon fonts that massively increase fingerprint uniqueness.
# The Asian/CJK fonts (AR PL UKai, AR PL UMing, etc.) made the font list 0.00% unique.
# Keep only standard Latin fonts (DejaVu, Liberation, Noto Sans/Serif).
RUN apt-get update && \
    apt-get purge -y \
        'fonts-arphic-*' \
        'fonts-noto-cjk*' \
        'fonts-noto-color-emoji' \
        'fonts-khmeros*' \
        'fonts-lohit-*' \
        'fonts-tlwg-*' \
        'fonts-sil-*' \
        'fonts-beng*' \
        'fonts-deva*' \
        'fonts-gujr*' \
        'fonts-guru*' \
        'fonts-knda*' \
        'fonts-mlym*' \
        'fonts-orya*' \
        'fonts-telu*' \
        'fonts-taml*' \
        'fonts-thai*' \
        'fonts-tibetan-machine' \
        'fonts-lklug-sinhala' \
        'fonts-smc*' \
        'fonts-gargi' \
        'fonts-navilu' \
        'fonts-nakula' \
        'fonts-sahadeva' \
        'fonts-samyak*' \
        'fonts-sarai' \
        'fonts-wqy-*' \
        'fonts-ipafont*' \
        'fonts-vlgothic' \
        'fonts-takao*' \
        'fonts-nanum*' \
        'fonts-unfonts-core' \
        'fonts-indic' 2>/dev/null || true && \
    apt-get autoremove -y && \
    fc-cache -f && \
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

# Copy fingerprint spoofing extension
COPY fingerprint-spoofer /opt/fingerprint-spoofer

# Create Brave supervisord config with privacy/fingerprint flags
# Key additions:
#   --lang=en-US                 : Fix content language from 0.57% → ~66%
#   --ignore-gpu-blocklist       : Allow Intel GPU for WebGL (avoid SwiftShader)
#   --enable-gpu-rasterization   : Use GPU for rendering
#   --enable-zero-copy           : Better GPU utilization
#   --load-extension             : Load fingerprint normalizer extension
#   --disable-background-networking : Reduce network fingerprinting
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
  --lang=en-US\n\
  --ignore-gpu-blocklist\n\
  --enable-gpu-rasterization\n\
  --enable-zero-copy\n\
  --load-extension=/opt/fingerprint-spoofer\n\
  --disable-background-networking\n\
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
