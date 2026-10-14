#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# Caelo CMS — one-click install from Google Cloud Shell.
#
#   ./run.sh gcp            # or: ./run.sh gcp-firebase
#   ./run.sh gcp --local    # run pulumi up in this terminal instead of the install job
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
#   5. Runs the installer. In install-job mode (the default here) it verifies
#      the release's signed manifest with cosign, does the steps that need
#      your Google login, shows the monthly cost and asks before creating
#      anything billable, then starts the install as a Cloud Run job in your
#      project and follows it. Closing this tab does not stop the install;
#      run this script again to follow it.
#
# The release's version pins are updated by this repository's
# track-release workflow; each pinned release gets a `release-v<version>`
# branch and a `v<version>` tag that the "Open in Cloud Shell" links name.

set -euo pipefail

CAELO_VERSION="0.10.50"

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
       ./run.sh --verify-only      (download + verify, do not run the installer)
USAGE
}

provider=""
verify_only=0
local_mode=0
passthrough=()
for arg in "$@"; do
  case "${arg}" in
    gcp | gcp-firebase) [ -z "${provider}" ] && provider="${arg}" || passthrough+=("${arg}") ;;
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
if [ "${verify_only}" = 0 ] && [ -z "${provider}" ]; then
  usage >&2
  exit 2
fi

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

work="${CAELO_INSTALL_DIR:-${HOME}/.caelo-install}"
bin="${work}/bin"
mkdir -p "${bin}"
chmod 700 "${work}"

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
rm -rf "${pkg}"
mkdir -p "${pkg}"
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
(cd "${pkg}" && npm install --ignore-scripts --no-audit --no-fund --loglevel=error)

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
