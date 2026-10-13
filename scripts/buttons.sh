#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# Print the README's "Open in Cloud Shell" block for a Caelo version — one
# button per provider, each pinned to that release's `release-v<version>`
# branch of this repository. track-release.yml writes it between the
# buttons markers in README.md; caelo-cms's docs use the same URL shape.
#
#   scripts/buttons.sh 0.10.47

set -euo pipefail
v="${1:?usage: scripts/buttons.sh <version>}"
[[ "${v}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "not a stable version: ${v}" >&2
  exit 2
}

url() {
  printf 'https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/caelo-cms/install&cloudshell_git_branch=release-v%s&cloudshell_tutorial=%s.md' "${v}" "$1"
}

cat <<BLOCK
Caelo **v${v}**:

| Provider | |
|---|---|
| Google Cloud — load balancer + Cloud CDN (\`gcp\`) | [![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)]($(url gcp)) |
| Google Cloud — Firebase Hosting (\`gcp-firebase\`) | [![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)]($(url gcp-firebase)) |
BLOCK
