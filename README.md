# Caelo CMS — one-click install

Install [Caelo CMS](https://github.com/caelo-cms/caelo-cms) in your own Google Cloud project from your browser: click the button, sign in, answer a few questions, confirm the cost. No laptop, no CLI to install, no service-account key.

<!-- buttons:start -->
Caelo **v0.10.49**:

| Provider | |
|---|---|
| Google Cloud — load balancer + Cloud CDN (`gcp`) | [![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/caelo-cms/install&cloudshell_git_branch=release-v0.10.49&cloudshell_tutorial=gcp.md) |
| Google Cloud — Firebase Hosting (`gcp-firebase`) | [![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/caelo-cms/install&cloudshell_git_branch=release-v0.10.49&cloudshell_tutorial=gcp-firebase.md) |
<!-- buttons:end -->

Each button opens Google Cloud Shell on a `release-v<version>` branch of this repository, with a step-by-step tutorial (`gcp.md`, `gcp-firebase.md`) next to the terminal. Full documentation: [caelo-cms.com/install-gcp](https://caelo-cms.com/install-gcp).

## What happens when you click

1. **Cloud Shell asks whether to trust this repository.** It is not a Google repository, so Cloud Shell opens it in a temporary session **without access to your Google credentials**, whichever answer you give. The tutorial's first step is signing in (`gcloud auth login --update-adc`).
2. **`./run.sh gcp`** (or `gcp-firebase`) — before anything runs:
   - downloads [Bun](https://bun.sh) and [cosign](https://github.com/sigstore/cosign) at pinned versions and checks each against its pinned SHA-256;
   - installs `@caelo-cms/provisioning` at the exact version the branch pins, with npm lifecycle scripts disabled;
   - runs `npm audit signatures`, which verifies the registry signature and the Sigstore provenance attestation of every installed package;
   - checks that the two Caelo packages' provenance names `github.com/caelo-cms/caelo-cms`, built on the tag `v<version>`.
3. **The installer** asks for the project, domain, owner email and region, sets up the project with your Google login, shows the **monthly cost** and asks before it creates anything billable.
4. **The install job.** The installer verifies the release's signed manifest with cosign (signed by Caelo's release workflow on that tag) and starts a Cloud Run job in your project, running the `caelo-ops` image pinned by the manifest's digest, as the project's `caelo-provisioner` service account. The job builds the infrastructure, waits for DNS and the certificate, and stores the Owner setup link in Secret Manager. Your terminal follows its log.

**Closing the tab does not stop the install.** Cloud Shell ends idle sessions after 40 minutes and the session's home directory is temporary; the install's state lives in your project (`gs://<project>-caelo-ops`). Open the same link again, sign in and run `./run.sh` with the same project: it attaches to the running install, shows the result of a finished one, or resumes one that stopped.

To run the infrastructure step in the Cloud Shell terminal itself instead of the job, pass `--local` (needs the Pulumi CLI in that shell).

## Versions

`run.sh` pins one Caelo release (`CAELO_VERSION`) together with the checksums of the tools it downloads. The [`track-release`](.github/workflows/track-release.yml) workflow checks every 30 minutes for a new stable Caelo release, verifies it with `./run.sh --verify-only` (the same checks as above, on a GitHub runner), then commits the new pin to `main` and creates the `release-v<version>` branch and the `v<version>` tag that the buttons name. It uses only this repository's own `GITHUB_TOKEN`; no token for another repository is stored anywhere. A ruleset keeps `release-v*` branches and `v*` tags from being moved or deleted.

Releases that predate the install job are never pinned (`run.sh --verify-only` exits 3 for them).

**Manual pin** (if the schedule is disabled — GitHub pauses scheduled workflows after 60 days without repository activity — or a release needs pinning right away): run the workflow from the Actions tab (`track-release` → *Run workflow*, optionally with a version), or re-enable it there.

## Security notes

- Nothing here holds a credential. The install job's definition carries the project id and nothing else; the job reads everything from the install's own bucket, which only you and `caelo-provisioner` can write.
- The tools `run.sh` downloads are pinned by checksum; the Caelo packages by version, registry signature and provenance; the job's image by the digest in a manifest signed by Caelo's release workflow.
- Report vulnerabilities as described in [caelo-cms's security policy](https://github.com/caelo-cms/caelo-cms/security/policy).

## License

[MPL-2.0](LICENSE), like Caelo CMS.
