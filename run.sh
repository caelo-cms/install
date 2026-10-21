#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# Caelo CMS — one-click install (and break-glass upgrade) from Google Cloud Shell.
#
#   ./run.sh gcp            # or: ./run.sh gcp-firebase
#   ./run.sh gcp --local    # run pulumi up in this terminal instead of the install job
#   ./run.sh upgrade [--project <id>] [--install <domain>]
#                           # upgrade an existing install to the pinned release
#
# What it does, in order (nothing here touches your cloud before step 5):
#   1. Downloads Bun and cosign at the versions pinned below and checks each
#      against its pinned SHA-256. A mismatch stops the script.
#   2. Installs @caelo-cms/provisioning at the pinned CAELO_VERSION from npm
#      (lifecycle scripts disabled) and runs `npm audit signatures`, which
#      verifies the registry signatures and the Sigstore provenance
#      attestations of every installed package.
#   3. Checks the provenance of the two Caelo packages names Caelo's release
#      workflow: repository caelo-cms/caelo-cms, ref refs/tags/v<version>.
#   4. Signs you in to Google Cloud if this shell isn't (a Cloud Shell opened
#      from a repository Google doesn't own starts without your credentials).
#   5. Runs the installer (`upgrade`: the upgrade, see below). In install-job mode (the default here) it verifies
#      the release's signed manifest with cosign, does the steps that need
#      your Google login, shows the monthly cost and asks before creating
#      anything billable, then starts the install as a Cloud Run job in your
#      project and follows it. Closing this tab does not stop the install;
#      run this script again to follow it.
#
# `upgrade` (caelo-cms/caelo-cms#816) is the break-glass path Settings →
# Updates links when the admin cannot install a release itself. It relies
# on nothing in $HOME surviving between runs (Cloud Shell may hand out a
# fresh, temporary home): steps 1-4 run every time, then it finds the
# install in the Owner's projects (the ones whose ops bucket holds
# install/install.json), attaches it from that bucket and runs
# `upgrade --version <pinned>`. No Application Default Credentials: the
# upgrade runs on gcloud's own login only.
#
# The release's version pins are updated by this repository's
# track-release workflow; each pinned release gets a `release-v<version>`
# branch and a `v<version>` tag that the "Open in Cloud Shell" links name.

set -euo pipefail

CAELO_VERSION="0.10.59"

BUN_VERSION="1.4.2"
# github.com/oven-sh/bun/releases/download/bun-v<version>/SHASUMS256.txt
BUN_SHA256_X64="c678040f14fe0440eb839d37cbd0ce4c051a32da72806ac97de6a6aab6bf728f" # bun-linux-x64-baseline.zip
BUN_SHA256_AARCH64="54328bbc2d9c8e0c9f892c544d66c57a83b84139e34909e5ee81758f1ac8fda7" # bun-linux-aarch64.zip

COSIGN_VERSION="3.1.3"
# github.com/sigstore/cosign/releases/download/v<version>/cosign_checksums.txt
COSIGN_SHA256_AMD64="4629c757b7618056f8ddd7e2625ae9fdd94c0372a65049520bc7d9df9efc7f71"
COSIGN_SHA256_ARM64="c5d324e091826b0d7a78eb16fef316450b4eb9aaec045611c08ba06f5e73220a"

SOURCE_REPOSITORY="https://github.com/caelo-cms/caelo-cms"
PACKAGES=("@caelo-cms/provisioning" "@caelo-cms/shared")

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() {
  printf '\033[31mError: %s\033[0m\n' "$*" >&2
  exit 1
}

usage() {
  cat <<USAGE
Usage: ./run.sh <gcp|gcp-firebase> [--local] [installer flags...]
       ./run.sh upgrade [--project <gcp-project-id>] [--install <domain>]
       ./run.sh --verify-only      (download + verify, do not run the installer)
USAGE
}

provider=""
upgrade=0
verify_only=0
local_mode=0
upgrade_project=""
upgrade_install=""
passthrough=()
while [ "$#" -gt 0 ]; do
  arg="$1"
  shift
  case "${arg}" in
    gcp | gcp-firebase | upgrade)
      # The first of these names the mode; any later one is the installer's.
      if [ -n "${provider}" ] || [ "${upgrade}" = 1 ]; then
        passthrough+=("${arg}")
      elif [ "${arg}" = upgrade ]; then
        upgrade=1
      else
        provider="${arg}"
      fi
      ;;
    --project | --install)
      [ "${upgrade}" = 1 ] || {
        passthrough+=("${arg}")
        continue
      }
      if [ "$#" = 0 ] || [ "${1#-}" != "$1" ]; then die "${arg} needs a value."; fi
      if [ "${arg}" = --project ]; then upgrade_project="$1"; else upgrade_install="$1"; fi
      shift
      ;;
    --verify-only) verify_only=1 ;;
    --local)
      local_mode=1
      passthrough+=("${arg}")
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) passthrough+=("${arg}") ;;
  esac
done
if [ "${verify_only}" = 0 ] && [ -z "${provider}" ] && [ "${upgrade}" = 0 ]; then
  usage >&2
  exit 2
fi
if [ "${upgrade}" = 1 ] && [ "${local_mode}" = 1 ]; then
  die "--local is for installs; ./run.sh upgrade never runs Pulumi."
fi
if [ "${upgrade}" = 1 ] && [ "${#passthrough[@]}" -gt 0 ]; then
  die "./run.sh upgrade takes only --project and --install (got: ${passthrough[*]})."
fi
# What to name in "run ... again" messages.
rerun="./run.sh ${provider:---verify-only}"
[ "${upgrade}" = 0 ] || rerun="./run.sh upgrade"

for tool in curl unzip npm node sha256sum; do
  command -v "${tool}" >/dev/null 2>&1 || die "${tool} is required (Cloud Shell has it; on another machine install it first)."
done
if [ "${verify_only}" = 0 ]; then
  command -v gcloud >/dev/null 2>&1 || die "gcloud is required (Cloud Shell has it)."
fi
if [ "${local_mode}" = 1 ]; then
  command -v pulumi >/dev/null 2>&1 ||
    die "--local runs Pulumi in this shell and needs the Pulumi CLI (https://www.pulumi.com/docs/install/). Without --local the install runs as a job in your project and needs nothing else."
fi

case "$(uname -m)" in
  x86_64 | amd64)
    bun_asset="bun-linux-x64-baseline"
    bun_sha="${BUN_SHA256_X64}"
    cosign_asset="cosign-linux-amd64"
    cosign_sha="${COSIGN_SHA256_AMD64}"
    ;;
  aarch64 | arm64)
    bun_asset="bun-linux-aarch64"
    bun_sha="${BUN_SHA256_AARCH64}"
    cosign_asset="cosign-linux-arm64"
    cosign_sha="${COSIGN_SHA256_ARM64}"
    ;;
  *) die "unsupported machine $(uname -m); run the installer from a Linux amd64/arm64 shell such as Cloud Shell." ;;
esac
[ "$(uname -s)" = "Linux" ] || die "run.sh is for Linux (Cloud Shell). On macOS run: bunx @caelo-cms/provisioning@${CAELO_VERSION}"

# Free space in MiB on the filesystem holding $1.
free_mib() { df -Pk "$1" | awk 'NR == 2 { print int($4 / 1024) }'; }

# Everything bulky here (Bun, cosign, ~500 MB of node_modules, npm's cache
# and logs) is re-downloaded and re-verified on every run, so it lives
# outside $HOME: Cloud Shell's home is a 5 GB disk that is often already
# full, while / has tens of GB. Only gcloud's sign-in and the installer's
# own state (~/.caelo-<install-id>, a few KB) are written to $HOME.
work="${CAELO_INSTALL_DIR:-${TMPDIR:-/tmp}/caelo-install-$(id -u)}"
bin="${work}/bin"
if [ -z "${CAELO_INSTALL_DIR:-}" ] && [ -d "${HOME}/.caelo-install" ]; then
  # Earlier versions of this script kept the same files in ~/.caelo-install.
  say "Removing ~/.caelo-install (left by an earlier installer; now kept in ${work})"
  rm -rf "${HOME}/.caelo-install"
fi
mkdir -p "${bin}"
if [ ! -O "${work}" ] || [ -L "${work}" ]; then
  die "${work} is not a directory owned by you; set CAELO_INSTALL_DIR to a directory of your own."
fi
chmod 700 "${work}"

# Every "Open in Cloud Shell" click with a fresh clone leaves another
# ~/cloudshell_open/install-N behind, each with its own copy of this
# repository; they fill Cloud Shell's 5 GB home over time. Remove the ones
# that are clones of this repository, never the one running now and never
# a directory that is something else.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
for clone in "${HOME}"/cloudshell_open/install "${HOME}"/cloudshell_open/install-*; do
  [ -d "${clone}/.git" ] || continue
  [ "$(cd "${clone}" && pwd -P)" = "${here}" ] && continue
  origin="$(git -C "${clone}" remote get-url origin 2>/dev/null || true)"
  case "${origin%.git}" in
    https://github.com/caelo-cms/install | git@github.com:caelo-cms/install)
      say "Removing ${clone} (an earlier copy of this repository)"
      rm -rf "${clone}"
      ;;
  esac
done

work_need=1536
work_free="$(free_mib "${work}")"
[ "${work_free}" -ge "${work_need}" ] ||
  die "the installer needs ${work_need} MB free in ${work}, but only ${work_free} MB are free. Set CAELO_INSTALL_DIR to a directory on a disk with more space."
if [ "${verify_only}" = 0 ]; then
  home_need=64
  home_free="$(free_mib "${HOME}")"
  [ "${home_free}" -ge "${home_need}" ] || die "your home directory is full: ${home_free} MB free, the installer needs ${home_need} MB there for the Google sign-in and the install's state (~/.caelo-*). Cloud Shell's home is limited to 5 GB. See what uses it:
    du -sh ~/* ~/.[!.]* 2>/dev/null | sort -h | tail
then delete what you no longer need and run ${rerun} again."
fi

# Download $1 to $3 and check it against the SHA-256 $2.
fetch_verified() {
  local url="$1" sha="$2" out="$3"
  curl -fsSL --retry 3 -o "${out}.part" "${url}"
  echo "${sha}  ${out}.part" | sha256sum -c --quiet - || {
    rm -f "${out}.part"
    die "checksum mismatch for ${url} — refusing to run it."
  }
  mv "${out}.part" "${out}"
}

say "Bun ${BUN_VERSION} + cosign ${COSIGN_VERSION} (checksum-pinned)"
# The checksum is published for the archive, not the binary, so Bun is
# extracted from a verified archive on every run: a binary left in the
# install dir is never trusted (or executed) before verification. The
# archive is kept and re-verified, so a re-run downloads only when needed.
bun_zip="${work}/${bun_asset}-${BUN_VERSION}.zip"
if [ ! -f "${bun_zip}" ] || ! echo "${bun_sha}  ${bun_zip}" | sha256sum -c --quiet - 2>/dev/null; then
  fetch_verified "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/${bun_asset}.zip" "${bun_sha}" "${bun_zip}"
fi
tmp="$(mktemp -d)"
unzip -q "${bun_zip}" -d "${tmp}"
install -m 0755 "${tmp}/${bun_asset}/bun" "${bin}/bun"
rm -rf "${tmp}"
if [ ! -x "${bin}/cosign" ] || ! echo "${cosign_sha}  ${bin}/cosign" | sha256sum -c --quiet - 2>/dev/null; then
  fetch_verified "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/${cosign_asset}" "${cosign_sha}" "${bin}/cosign"
  chmod 0755 "${bin}/cosign"
fi
export PATH="${bin}:${PATH}"

say "@caelo-cms/provisioning@${CAELO_VERSION} from npm"
pkg="${work}/caelo-${CAELO_VERSION}"
rm -rf "${work}"/caelo-* "${work}/npm-logs"
mkdir -p "${pkg}"
# npm's cache and logs default to ~/.npm; keep them with the rest (see $work).
export npm_config_cache="${work}/npm-cache"
export npm_config_logs_dir="${work}/npm-logs"
# Exact versions for both Caelo packages: the published provisioning package
# depends on ^<version> of shared, which could otherwise resolve to a newer one.
cat >"${pkg}/package.json" <<JSON
{
  "name": "caelo-install-runner",
  "private": true,
  "dependencies": { "@caelo-cms/provisioning": "${CAELO_VERSION}" },
  "overrides": { "@caelo-cms/shared": "${CAELO_VERSION}" }
}
JSON
if ! (cd "${pkg}" && npm install --ignore-scripts --no-audit --no-fund --loglevel=error); then
  # --loglevel=error keeps a good run quiet, but on failure npm prints only
  # the log's path; surface the cause here.
  grep -h -E ' (error|verbose stack) ' "${work}"/npm-logs/*.log 2>/dev/null | tail -n 20 >&2 || true
  die "npm could not install @caelo-cms/provisioning@${CAELO_VERSION} (cause above; full log in ${work}/npm-logs). Fix what it names and run ${rerun} again."
fi

say "Verifying registry signatures + provenance (npm audit signatures)"
(cd "${pkg}" && npm audit signatures)

say "Checking the Caelo packages were built by ${SOURCE_REPOSITORY} at v${CAELO_VERSION}"
for name in "${PACKAGES[@]}"; do
  node - "${pkg}" "${name}" "${CAELO_VERSION}" "${SOURCE_REPOSITORY}" <<'NODE'
const [dir, name, version, repo] = process.argv.slice(2);
const installed = require(`${dir}/node_modules/${name}/package.json`).version;
if (installed !== version) {
  console.error(`${name}: installed ${installed}, expected ${version}`);
  process.exit(1);
}
(async () => {
  const url = `https://registry.npmjs.org/-/npm/v1/attestations/${encodeURIComponent(name)}@${version}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${name}@${version}: no provenance attestation (${url}: HTTP ${res.status})`);
  const { attestations } = await res.json();
  const slsa = attestations.find((a) => a.predicateType === "https://slsa.dev/provenance/v1");
  if (!slsa) throw new Error(`${name}@${version}: no SLSA provenance`);
  const statement = JSON.parse(Buffer.from(slsa.bundle.dsseEnvelope.payload, "base64").toString("utf8"));
  const workflow = statement.predicate?.buildDefinition?.externalParameters?.workflow ?? {};
  const subject = (statement.subject ?? []).map((s) => s.name);
  const wantSubject = `pkg:npm/${name.replace("@", "%40")}@${version}`;
  if (workflow.repository !== repo || workflow.ref !== `refs/tags/v${version}` || !subject.includes(wantSubject)) {
    throw new Error(
      `${name}@${version} was not built by ${repo} at refs/tags/v${version} (provenance: ${workflow.repository} ${workflow.ref}, ${subject.join(",")})`,
    );
  }
  console.log(`  ${name}@${version}: ${workflow.repository} ${workflow.ref} (${workflow.path})`);
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
NODE
done

cli="${pkg}/node_modules/@caelo-cms/provisioning/dist/cli.js"
if [ ! -f "${pkg}/node_modules/@caelo-cms/provisioning/dist/install-job-runner.js" ]; then
  printf '\033[31mError: %s\033[0m\n' "Caelo v${CAELO_VERSION} predates the Cloud Shell install (no install job). Use a newer release's link, or run the installer on your machine: bunx @caelo-cms/provisioning@${CAELO_VERSION}" >&2
  exit 3 # track-release.yml: a release without the install job is not pinned
fi

if [ "${verify_only}" = 1 ]; then
  say "Verified Caelo v${CAELO_VERSION} (not running the installer: --verify-only)"
  exit 0
fi

if [ "${upgrade}" = 1 ]; then
  # A valid token, not just an account: credentials that expired (or a
  # temporary session without them) still list the account (#630).
  if ! gcloud auth print-access-token --quiet >/dev/null 2>&1; then
    say "Sign in to Google Cloud"
    echo "This Cloud Shell has no valid sign-in for your Google account. Open the link below, sign in"
    echo "with the Owner's Google account (the one that installed Caelo), and paste the code back here."
    gcloud auth login
    gcloud auth print-access-token --quiet >/dev/null 2>&1 ||
      die "gcloud still has no valid sign-in. Run \`gcloud auth login\`, then ${rerun} again."
  fi

  # The install's own records: <project>-caelo-ops/install/install.json.
  # Prints "<project> <domain>" when project $1 has them, nothing otherwise
  # (no bucket, no access: both mean "not this project", so the status is
  # always 0 under pipefail).
  install_record() {
    { gcloud storage cat "gs://$1-caelo-ops/install/install.json" </dev/null 2>/dev/null || true; } |
      node -e 'let t="";process.stdin.on("data",(c)=>(t+=c)).on("end",()=>{try{const j=JSON.parse(t);if(j.projectId===process.argv[1]&&typeof j.domain==="string")console.log(j.projectId+" "+j.domain)}catch{}})' "$1"
  }
  found=()
  if [ -n "${upgrade_project}" ]; then
    rec="$(install_record "${upgrade_project}")"
    [ -n "${rec}" ] || die "project ${upgrade_project} has no Caelo install records (gs://${upgrade_project}-caelo-ops/install/install.json), or this account may not read them. Check the project id, and that you are signed in as the Owner ($(gcloud config get-value account 2>/dev/null))."
    found=("${rec}")
  else
    say "Looking for your Caelo install in the projects this account can see"
    while IFS= read -r p; do
      [ -n "${p}" ] || continue
      rec="$(install_record "${p}")"
      [ -z "${rec}" ] || found+=("${rec}")
    done < <(gcloud projects list --filter=lifecycleState:ACTIVE --format='value(projectId)' 2>/dev/null)
  fi
  if [ -n "${upgrade_install}" ]; then
    matching=()
    for rec in "${found[@]}"; do
      [ "${rec#* }" = "${upgrade_install}" ] && matching+=("${rec}")
    done
    [ "${#matching[@]}" -gt 0 ] || die "no Caelo install for ${upgrade_install} in ${upgrade_project:-the projects this account can see}. Pass --project <the install's project id>."
    found=("${matching[@]}")
  fi
  case "${#found[@]}" in
    0) die "no Caelo install found in the projects $(gcloud config get-value account 2>/dev/null) can see. Pass --project <the install's project id>, signed in as the Owner." ;;
    1) chosen="${found[0]}" ;;
    *)
      [ -t 0 ] || die "this account can see several Caelo installs (${found[*]}). Pass --project <id>."
      echo "Several Caelo installs:"
      for i in "${!found[@]}"; do echo "  $((i + 1))) ${found[${i}]#* } (project ${found[${i}]%% *})"; done
      read -r -p "Which one should be upgraded? [1-${#found[@]}] " pick
      if ! [[ "${pick}" =~ ^[0-9]+$ ]] || [ "${pick}" -lt 1 ] || [ "${pick}" -gt "${#found[@]}" ]; then
        die "no install picked; nothing was changed."
      fi
      chosen="${found[$((pick - 1))]}"
      ;;
  esac
  project="${chosen%% *}"
  domain="${chosen#* }"

  say "Attaching ${domain} (project ${project}) from its records in gs://${project}-caelo-ops"
  "${bin}/bun" "${cli}" attach --project "${project}"
  say "Upgrading ${domain} to Caelo v${CAELO_VERSION}"
  exec "${bin}/bun" "${cli}" upgrade --version "${CAELO_VERSION}" --install "${domain}"
fi

if [ -z "$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null)" ]; then
  say "Sign in to Google Cloud"
  echo "This Cloud Shell has no access to your Google account yet. Open the link below, sign in"
  echo "with the account that owns (or will own) the project, and paste the code back here."
  gcloud auth login --update-adc
fi

mode_flag=()
[ "${local_mode}" = 1 ] || mode_flag=(--install-job)
say "Starting the Caelo installer (v${CAELO_VERSION}, ${provider})"
exec "${bin}/bun" "${cli}" --provider "${provider}" "${mode_flag[@]}" "${passthrough[@]}"
