# Samizdat-Plugin-Fortnox

Fortnox accounting integration for [Samizdat](https://fakenews.com) — operator
back-office (customers, invoices, payments, OAuth2). Extracted from the Samizdat
monorepo with history; installs as a standalone CPAN/pkg distribution.

## Layout

    lib/Samizdat/Plugin/Fortnox.pm         routes + the `fortnox` helper
    lib/Samizdat/Controller/Fortnox.pm     request handlers (incl. the OAuth callback)
    lib/Samizdat/Model/Fortnox.pm          Fortnox API client
    lib/Samizdat/Command/fortnox.pm        `samizdat fortnox` sync command
    lib/Samizdat/resources/templates/fortnox/   views (shipped, install to site_perl)
    lib/Samizdat/resources/settings/fortnox/    JSON-Schema config contract
    lib/Samizdat/resources/locale/fortnox/      per-module translations

Resources install under `site_perl/Samizdat/resources/...`, where the core
resolver (`$app->resource(...)`) finds them.

## Dependencies

- **Samizdat** (core) — provides `Samizdat::Model::Cache` and the settings
  resolver. Not yet on CPAN; install the core dist or put it on `PERL5LIB`.
- Mojolicious, Hash::Merge.

## Install

    perl Makefile.PL
    make && make test          # core (Samizdat) must be on PERL5LIB
    make install               # or: make install INSTALL_BASE=/path/to/prefix

Enable it in `samizdat.yml` via `extraplugins: [Fortnox]` and configure
`manager.fortnox` (see `lib/Samizdat/resources/settings/fortnox/schema.yml` for
the defaults and required `oauth2.client_id` / `oauth2.secret`).
