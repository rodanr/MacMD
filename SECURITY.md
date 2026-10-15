# Security policy

## Supported versions

Security fixes go into the latest release.

## Reporting a vulnerability

Please **don't open a public issue**. Report it privately through
[GitHub security advisories](https://github.com/rodanr/macmd/security/advisories/new) with steps to
reproduce. You'll get a reply within a week.

## Scope notes

MacMD opens untrusted Markdown files. In Read mode:
- scripts run only from the app bundle (Content Security Policy);
- the page can't navigate away from the document;
- local links never launch apps; they are revealed in Finder;
- the `macmd://file` handler serves only images and media.

Anything that executes script from a document, reads files the user didn't open, launches an app, or gets
past one of these rules is a security bug we want to hear about.
