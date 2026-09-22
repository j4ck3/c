# charts.d module: system uptime in days (for custom dashboard cards).
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck shell=bash

uptime_days_update_every=10
uptime_days_priority=999

uptime_days_value=0

uptime_days_get() {
  local secs
  if [ -r /host/proc/uptime ]; then
    secs=$(cut -d. -f1 /host/proc/uptime)
  elif [ -r /proc/uptime ]; then
    secs=$(cut -d. -f1 /proc/uptime)
  else
    return 1
  fi
  uptime_days_value=$(awk -v s="${secs}" 'BEGIN { printf "%.1f", s / 86400 }')
  return 0
}

uptime_days_check() {
  uptime_days_get
}

uptime_days_create() {
  cat <<EOF
CHART custom.uptime_days '' "System Uptime" days uptime custom.uptime_days line ${uptime_days_priority} ${uptime_days_update_every}
DIMENSION days '' absolute 1 1
EOF
  return 0
}

uptime_days_update() {
  uptime_days_get || return 1
  cat <<VALUESEOF
BEGIN custom.uptime_days $1
SET days = ${uptime_days_value}
END
VALUESEOF
  return 0
}
