#!/bin/sh
set -eu

DSH_HOME="${DSH_HOME:-${HOME}/.dsh}"
profile_dir="${DSH_HOME}/profiles/open-design"
profile_manifest="${profile_dir}/node_modules/@open-design/dsh-runtime/package.json"
profile_patch="${profile_dir}/cordis.patch.yml"
runtime_package="/opt/open-design/dsh-runtime.tgz"

mkdir -p "${HOME}" "${DSH_HOME}"
installed_version="$([ -f "${profile_manifest}" ] && node -p "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')).version" "${profile_manifest}" 2>/dev/null || true)"
if [ "${installed_version}" != "0.1.0" ] || ! grep -q '@open-design/dsh-runtime' "${profile_patch}" 2>/dev/null; then
  echo "open-design: installing DeepSeek Harness runtime (was ${installed_version:-missing})"
  dsh plugin --profile open-design add "${runtime_package}"
fi

echo "open-design: DeepSeek Harness $(dsh --version) with runtime ${installed_version:-0.1.0}"
exec "$@"
