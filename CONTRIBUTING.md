# Contributing to floresta-nix

We welcome contributions in many forms: bug reports, feature requests, code, and documentation. From contributors with any level of experience. We only ask that you respect others and follow the process outlined here.

## Communications Channels

The primary communication channel is the [GitHub repository](https://github.com/getfloresta/floresta-nix). You can also reach us on [Discord](https://discord.gg/5Wj8fjjS93).

## Contribution Workflow

0. Create or find a issue to address.
1. Fork the repository
2. Create a topic branch
3. Commit patches

### Commits

Commits should be atomic and diffs should be easy to read. Do not mix formatting fixes with actual code changes. Each commit should evaluate cleanly with `nix flake check`.

Commits follow ["Conventional Commits 1.0.0"](https://www.conventionalcommits.org/en/v1.0.0/). The types we use:

- chore: maintenance tasks
- ci: continuous integration
- docs: documentation changes
- feat: new feature
- fix: bug fix
- refactor: code change that neither fixes a bug nor adds a feature

For `scope`, consider:

- flake
- build (for `lib/floresta-build.nix`)
- service (for `lib/floresta-service.nix`)
- ci
- examples

It is required to [GPG sign](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits) your commits.

## Peer Review

Pull requests need to be reviewed by at least one maintainer. We follow the same review conventions as [Floresta](https://github.com/getfloresta/Floresta/blob/master/CONTRIBUTING.md#peer-review).

## Coding Conventions

This is a Nix-only repository. All `.nix` files must pass the pre-commit hooks enforced by CI and offered by the checks in the devshell:

- **nixfmt-rfc-style**: formatting
- **deadnix**: unused code detection
- **nil**: Nix language diagnostics
- **statix**: anti-pattern linting

You can run them locally by entering the dev shell:

```sh
nix develop
```

The hooks run automatically on each commit via the shell hook.

## Testing

Before submitting, make sure `nix flake check` passes. If your change affects the build library, verify that `examples/flake.nix` still evaluates correctly.

## LLM and AI Agent Usage

This project does not accept contributions from AI bots. All PRs that appear to come from such accounts will be closed and potentially banned if configured as an obstacle to the development of the project.

Patches created by LLMs and AI agents are also viewed with suspicion.
All LLM generated patches MUST have text in the git log and in the PR description that indicates the
patch was created using an LLM. First time contributions by way of LLM generated patches are not welcome.

Thanks for your time, please be respectful of ours.
