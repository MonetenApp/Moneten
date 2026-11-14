# Website

This folder holds the static website for monetenapp.com, in German. It has no build step, no scripts, and no resources from other hosts, so the privacy page can say that the site sets no cookies and loads nothing from other servers.

- `index.html` presents the app, the extensions, and the state of the project.
- `impressum.html` and `datenschutz.html` are the legal pages of Adanos Software GmbH, which runs the site.
- `style.css` takes its colors from the app icon and follows the light or dark appearance of the system.
- `img/` holds the app icon, the screenshots as WebP in a light and a dark version, and `og-image.jpg` for link previews.

The workflow `.github/workflows/website.yml` publishes the folder to GitHub Pages on every push to `main` that changes it. Before its first run:

1. Set the Pages source of the repository to "GitHub Actions".
2. Set the custom domain to monetenapp.com and turn on "Enforce HTTPS".
3. Point the DNS records of monetenapp.com to GitHub Pages, and add a `www` CNAME record to `monetenapp.github.io`.

If the workflow ran before Pages was on, it failed, and nothing publishes the site until the next change in this folder. Start the workflow "Website" by hand in the Actions tab.

## Screenshots

The screenshots show the made-up data of the debug harness, never real accounts. To make new ones, build the app with `scripts/build-app.sh debug`, start it with `MONETEN_DATA_DIR` and `MONETEN_DEBUG_DIR` set to empty folders and the arguments `"-NSWindow Frame main" "120 60 1440 900 0 0 1800 1130"`, which open the main window at 1440 by 900 points, send the commands `create`, `seed`, `select Girokonto`, `appearance light` or `appearance dark`, and `view list` or `view barChart`, and capture the window with `screencapture -o -l <window number>`. Scale the images to 2080 pixels wide and convert them with `cwebp -q 88`.

Check a change by opening `index.html` in a browser, in the light and the dark appearance and at the width of a phone.
