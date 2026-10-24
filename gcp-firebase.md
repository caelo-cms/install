# Install Caelo CMS on Google Cloud (Firebase Hosting)

<walkthrough-tutorial-duration duration="30"></walkthrough-tutorial-duration>

This installs Caelo CMS in your own Google Cloud project, with the public site on Firebase Hosting (no load balancer, so a lower fixed cost): Cloud Run for the admin and the API gateway, Cloud SQL Postgres, Firebase Hosting for the site, Secret Manager, and Google IAP in front of the admin.

You need:

- a Google account that can create a project and link a billing account (or that owns a project with billing),
- a domain you control, where you can add DNS records.

The installer shows the monthly cost (about $14/mo for the default setup, before AI usage and traffic) and asks before it creates anything that costs money.

Click **Start** to begin.

## Run the installer

```bash
./run.sh gcp-firebase
```

Before anything runs, `run.sh` downloads Bun and cosign at pinned versions and checks their checksums, installs `@caelo-cms/provisioning` at the newest stable Caelo release (it prints which), and verifies with `npm audit signatures` that it was built from `github.com/caelo-cms/caelo-cms` by Caelo's release workflow. If this shell is not signed in to Google Cloud yet, it asks you to sign in (open the link it prints, sign in with the account that owns or will own the project, paste the code back). Then the installer asks for:

1. the **Google Cloud project id**: a new one is created for you; an existing one is reused,
2. your **domain**, the **staging host** and the **owner email** (the Google account that may open the admin),
3. the **region** where your data lives (fixed after install),
4. the **billing account**, if you have more than one.

It then sets up the project and shows the **estimated monthly cost**. Nothing billable exists until you confirm.

## Let the install run

After you confirm, the installer starts a Cloud Run job named `caelo-install` in your project and shows its progress here. The job builds the infrastructure (about 10-15 minutes). It does not wait for DNS: the admin starts on its Cloud Run URL, so you can try Caelo before your domain points anywhere.

**You can close this tab.** The install keeps running in your project: Ctrl-C, a closed tab and Cloud Shell's 40-minute idle timeout do not stop it. To follow it again, open the same "Open in Cloud Shell" link and run `./run.sh gcp-firebase` with the same project id. It attaches to the running install, or shows the result if it has finished.

## DNS records (later)

No DNS record is needed to finish the install. When the job is done, the summary lists the records for your domain: set them when your new site is ready to go live, and Firebase Hosting issues the certificate once they point at it. Do not move your main domain while a website is live there today.

The admin's own `admin.<domain>` host and the protected staging host are optional; the summary prints the command that sets up each one (`admin-domain enable`, `staging-domain enable`) and the record it needs.

## Finish

When the job is done, this terminal shows the **Owner setup link**. Open it and sign in with the owner email to create your Owner account. Then add your Anthropic API key at **Settings → AI** in the admin.

If the run stopped with an error, fix what it names and run `./run.sh gcp-firebase` again: it resumes where it stopped.

Troubleshooting: https://caelo-cms.com/docs/install/google-cloud/

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>
