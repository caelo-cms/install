# Install Caelo CMS on Google Cloud

<walkthrough-tutorial-duration duration="30"></walkthrough-tutorial-duration>

This installs Caelo CMS in your own Google Cloud project: Cloud Run for the admin and the API gateway, Cloud SQL Postgres, Cloud Storage behind Cloud CDN and a load balancer, Secret Manager, and Google IAP in front of the admin.

You need:

- a Google account that can create a project and link a billing account (or that owns a project with billing),
- a domain you control, where you can add DNS records.

The installer shows the monthly cost (about $33/mo for the default setup, before AI usage and traffic) and asks before it creates anything that costs money.

Click **Start** to begin.

## Run the installer

```bash
./run.sh gcp
```

Before anything runs, `run.sh` downloads Bun and cosign at pinned versions and checks their checksums, installs `@caelo-cms/provisioning` at the version this link is pinned to, and verifies with `npm audit signatures` that it was built from `github.com/caelo-cms/caelo-cms` by Caelo's release workflow. If this shell is not signed in to Google Cloud yet, it asks you to sign in (open the link it prints, sign in with the account that owns or will own the project, paste the code back). Then the installer asks for:

1. the **Google Cloud project id**: a new one is created for you; an existing one is reused,
2. your **domain**, the **staging host** and the **owner email** (the Google account that may open the admin),
3. the **region** where your data lives (fixed after install),
4. the **billing account**, if you have more than one.

It then sets up the project and shows the **estimated monthly cost**. Nothing billable exists until you confirm.

## Let the install run

After you confirm, the installer starts a Cloud Run job named `caelo-install` in your project and shows its progress here. The job builds the infrastructure (about 10-15 minutes), then waits for DNS and the TLS certificate.

**You can close this tab.** The install keeps running in your project: Ctrl-C, a closed tab and Cloud Shell's 40-minute idle timeout do not stop it. To follow it again, open the same "Open in Cloud Shell" link and run `./run.sh gcp` with the same project id. It attaches to the running install, or shows the result if it has finished.

## Set the DNS records

When the job reaches **Waiting for DNS**, it prints the records to set at your registrar (the admin host first). Set them; the job notices on its own once they resolve (it waits up to two hours) and continues with the certificate.

Domain on Cloudflare? Run `export CLOUDFLARE_API_TOKEN=<token with Zone:DNS:Edit>` before `./run.sh` and the install sets these records itself (the token is kept in Secret Manager in your project for the job).

Do not move your main domain yet if a website is live there today. The installer lists those records separately, for when your new site is published.

## Finish

When the job is done, this terminal shows the **Owner setup link**. Open it and sign in with the owner email to create your Owner account. Then add your Anthropic API key at **Settings → AI** in the admin.

If the run stopped with an error, fix what it names and run `./run.sh gcp` again: it resumes where it stopped.

Troubleshooting: https://caelo-cms.com/install-gcp#common-issues

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>
