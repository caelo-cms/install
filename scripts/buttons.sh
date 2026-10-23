#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# Print an "Open in Cloud Shell" block — one button per provider.
#
#   scripts/buttons.sh            # install buttons: `main`, the newest release
#   scripts/buttons.sh 0.10.47    # buttons for exactly that release
#
# Install links name `main`: run.sh there resolves the newest stable release
# itself, so the buttons never carry a version and never need moving. A
# version gives the `release-v<version>` branch track-release.yml creates,
# for the rare link that must install one particular release.

set -euo pipefail
branch="main"
if [ "$#" -gt 0 ]; then
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "not a stable version: $1" >&2
    exit 2
  }
  branch="release-v$1"
fi

url() {
  printf 'https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/caelo-cms/install&cloudshell_git_branch=%s&cloudshell_tutorial=%s.md' "${branch}" "$1"
}

cat <<BLOCK
| Provider | |
|---|---|
| Google Cloud — load balancer + Cloud CDN (\`gcp\`) | [![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)]($(url gcp)) |
| Google Cloud — Firebase Hosting (\`gcp-firebase\`) | [![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)]($(url gcp-firebase)) |
BLOCK
