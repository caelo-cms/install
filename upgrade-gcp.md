# Upgrade Caelo CMS on Google Cloud

<walkthrough-tutorial-duration duration="20"></walkthrough-tutorial-duration>

This upgrades the Caelo site you already run to the release this link is pinned to. It is the break-glass path: use it when **Settings → Updates** in your admin sends you here, because the release needs a change that only your own Google account may make in your project.

It does not install anything new and it does not ask for a project to create. It finds your site in your Google Cloud project, backs up its database, and rolls it forward. If the new release fails its health check, your site goes back to the release it runs now.

Click **Start** to begin.

## Run the upgrade

```bash
./run.sh upgrade
```

Settings → Updates shows the same line with your project and site filled in (`./run.sh upgrade --project <id> --install <domain>`); use that one if your Google account can see more than one Caelo site.

What `run.sh` does, in order:

1. Checks the free disk space, and removes earlier copies of this repository that Cloud Shell left in your home directory.
2. Downloads Bun and cosign at pinned versions and checks their checksums, installs `@caelo-cms/provisioning` at the version this link is pinned to, and verifies with `npm audit signatures` that it was built from `github.com/caelo-cms/caelo-cms` by Caelo's release workflow. This runs every time: nothing from an earlier session is trusted or needed.
3. Checks that this shell is signed in to Google Cloud. If it is not (Cloud Shell opens this repository in a session without your credentials), it prints a link: open it, sign in with the Google account that owns your Caelo site, and paste the code back.
4. Finds your site: the project whose `<project>-caelo-ops` bucket holds the install's records. If your account can see several, it asks which one.
5. Attaches the site from those records, then runs the upgrade: it verifies the release's image signatures, backs up the Cloud SQL database, applies what the release needs in your project, switches the admin and the API gateway to the new release, and tests them.

It takes about 10 to 20 minutes. Your public site stays online the whole time.

## When it has finished

The last lines name the release your site runs now. Open your admin: **Settings → Updates** shows the new version.

If the upgrade stopped with an error, it says what was changed (usually nothing) and what to fix. Fix it and run `./run.sh upgrade` again; it is safe to repeat. A database backup taken before the change is named in the output, with the command that restores it.

Troubleshooting: https://caelo-cms.com/docs/install/maintenance/

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>
