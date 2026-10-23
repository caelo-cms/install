# Caelo CMS — one-click install

Install [Caelo CMS](https://github.com/caelo-cms/caelo-cms) in your own Google Cloud project from your browser: click the button, sign in, answer a few questions, confirm the cost. No laptop, no CLI to install, no service-account key.

<!-- buttons:start -->
| Provider | |
|---|---|
| Google Cloud — load balancer + Cloud CDN (`gcp`) | [![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/caelo-cms/install&cloudshell_git_branch=main&cloudshell_tutorial=gcp.md) |
| Google Cloud — Firebase Hosting (`gcp-firebase`) | [![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/caelo-cms/install&cloudshell_git_branch=main&cloudshell_tutorial=gcp-firebase.md) |
<!-- buttons:end -->

Each button opens Google Cloud Shell on this repository's `main` branch, which always installs the newest stable Caelo release, with a step-by-step tutorial (`gcp.md`, `gcp-firebase.md`) next to the terminal. Full documentation: [caelo-cms.com/install-gcp](https://caelo-cms.com/install-gcp).

## What happens when you click

1. **Cloud Shell asks whether to trust this repository.** It is not a Google repository, so Cloud Shell opens it in a temporary session **without access to your Google credentials**, whichever answer you give. The tutorial's first step is signing in (`gcloud auth login --update-adc`).
2. **`./run.sh gcp`** (or `gcp-firebase`) — before anything runs:
   - downloads [Bun](https://bun.sh) and [cosign](https://github.com/sigstore/cosign) at pinned versions and checks each against its pinned SHA-256;
   - installs `@caelo-cms/provisioning` at the newest stable release (the npm `latest` dist-tag), exactly that version, with npm lifecycle scripts disabled;
   - runs `npm audit signatures`, which verifies the registry signature and the Sigstore provenance attestation of every installed package;
   - checks that the two Caelo packages' provenance names `github.com/caelo-cms/caelo-cms`, built on the tag `v<version>`.
3. **The installer** asks for the project, domain, owner email and region, sets up the project with your Google login, shows the **monthly cost** and asks before it creates anything billable.
4. **The install job.** The installer verifies the release's signed manifest with cosign (signed by Caelo's release workflow on that tag) and starts a Cloud Run job in your project, running the `caelo-ops` image pinned by the manifest's digest, as the project's `caelo-provisioner` service account. The job builds the infrastructure, waits for DNS and the certificate, and stores the Owner setup link in Secret Manager. Your terminal follows its log.

**Closing the tab does not stop the install.** Cloud Shell ends idle sessions after 40 minutes and the session's home directory is temporary; the install's state lives in your project (`gs://<project>-caelo-ops`). Open the same link again, sign in and run `./run.sh` with the same project: it attaches to the running install, shows the result of a finished one, or resumes one that stopped.

To run the infrastructure step in the Cloud Shell terminal itself instead of the job, pass `--local` (needs the Pulumi CLI in that shell).

## Upgrading an install (break-glass)

When a release needs a change that only the Owner's own Google account may make, **Settings → Updates** in the admin shows an **Open Google Cloud Shell** button. It opens this repository on the release's `release-v<version>` branch with the upgrade walkthrough (`upgrade-gcp.md`, `upgrade-gcp-firebase.md`), never the install one. The walkthrough runs one command:

```bash
./run.sh upgrade [--project <gcp-project-id>] [--install <domain>]
```

It runs the same verified bootstrap as the installer (checksum-pinned Bun and cosign, `npm audit signatures`, provenance), checks the free disk space and removes earlier clones of this repository from `~/cloudshell_open`, checks that gcloud has a valid sign-in (and asks you to sign in if not), finds the install in your projects (the one whose `<project>-caelo-ops` bucket holds `install/install.json`; it asks if there are several), attaches it from that bucket and runs `upgrade --version <the branch's release>`. It needs nothing to survive in your home directory between sessions, and no Application Default Credentials.

## Versions

Nothing in this repository names a Caelo version. `run.sh` resolves the release to run, in this order:

1. `--version <x.y.z>`, when given;
2. the release a `release-v<version>` checkout names (the links Settings → Updates opens for one target release);
3. otherwise the newest stable release: the `latest` dist-tag of `@caelo-cms/provisioning` on npm. Caelo's release workflow moves it only after the release's images and signed manifest are published, and never for a pre-release.

Whatever it resolves goes through the same checks (registry signatures, provenance on the tag `v<version>`, the signed manifest) before anything runs. Only the tools it downloads are pinned, by checksum.

The [`track-release`](.github/workflows/track-release.yml) workflow checks every 30 minutes for a new stable Caelo release, verifies it with `./run.sh --verify-only --version <v>` on a GitHub runner, and creates its `release-v<version>` branch, a plain pointer with no commit of its own. It uses only this repository's own `GITHUB_TOKEN`. A ruleset keeps `release-v*` branches from being moved or deleted. Releases that predate the install job get no branch (`run.sh --verify-only` exits 3 for them).

**Manual run** (if the schedule is disabled — GitHub pauses scheduled workflows after 60 days without repository activity — or a branch is needed right away): run the workflow from the Actions tab (`track-release` → *Run workflow*, optionally with a version), or re-enable it there. The install buttons do not wait for it: they install the newest release as soon as it is on npm.

## Security notes

- Nothing here holds a credential. The install job's definition carries the project id and nothing else; the job reads everything from the install's own bucket, which only you and `caelo-provisioner` can write.
- The tools `run.sh` downloads are pinned by checksum; the Caelo packages by version, registry signature and provenance; the job's image by the digest in a manifest signed by Caelo's release workflow.
- Report vulnerabilities as described in [caelo-cms's security policy](https://github.com/caelo-cms/caelo-cms/security/policy).

## License

[MPL-2.0](LICENSE), like Caelo CMS.
