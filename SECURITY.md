# Security policy

## Reporting a vulnerability

Do not report security vulnerabilities, exposed credentials, or sensitive data
in public issues, discussions, or pull requests.

Report them privately through
[GitHub private vulnerability reporting](https://github.com/rbrunois/agentic-itops-showcase/security/advisories/new).
Include:

- the affected use case and file paths;
- a description of the issue and its potential impact;
- reproduction steps or a proof of concept, without real secrets or customer data.

The maintainers aim to acknowledge reports within five business days and will
coordinate a fix and disclosure timeline with you.

## Scope

This repository contains demonstrations, not supported products. In scope:

- secrets, credentials, or real identifiers committed to the repository;
- scripts, infrastructure as code, or workflows that grant broader access than
  documented, bypass a documented approval gate, or expose resources unexpectedly;
- agent instructions that can be induced to perform undocumented write actions.

Intentionally insecure lab settings that are documented as such (for example,
the legacy application used for fault scenarios in use case 05) are out of
scope, provided they remain isolated as documented.

## Safe use

- Deploy demos only to dedicated, non-production subscriptions.
- Store secrets in an approved secret store; never commit them.
- Review generated proposals, patches, and pull requests before applying them.
