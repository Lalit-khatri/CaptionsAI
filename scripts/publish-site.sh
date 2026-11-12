#!/bin/bash
# Publishes PRIVACY.md to the public site repository (GitHub Pages).
#
# PRIVACY.md here is the source of truth: the app bundles it and the site
# serves it at https://lalit-khatri.github.io/captionsai-site/privacy/.
# Run this after changing it, then push the site repository.
#
#   scripts/publish-site.sh ../captionsai-site
set -euo pipefail

site="${1:?usage: scripts/publish-site.sh <path to captionsai-site checkout>}"
here="$(cd "$(dirname "$0")/.." && pwd)"

{
  printf -- '---\nlayout: default\ntitle: Privacy Policy — CaptionsAI\npermalink: /privacy/\n---\n\n'
  cat "$here/PRIVACY.md"
} > "$site/privacy.md"

echo "Updated $site/privacy.md. Review, commit and push it there."
