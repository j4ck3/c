#!/bin/sh
# Rebuild Slate CSS and minified JS. Needs lessc + clean-css plugin and terser (npx).
set -eu
cd "$(dirname "$0")"
LESSC="${LESSC:-npx lessc}"
$LESSC --clean-css="--s1 --advanced" styles/styles.less > styles/styles.min.css
$LESSC --clean-css="--s1 --advanced" styles/print.less > styles/print.min.css
$LESSC --clean-css="--s1 --advanced" styles/embed.less > styles/embed.min.css
npx --yes terser ui.js -c -m -o ui.min.js
npx --yes terser slate.js -c -m -o slate.min.js
npx --yes terser slate-prefetch.js -c -m -o slate-prefetch.min.js
