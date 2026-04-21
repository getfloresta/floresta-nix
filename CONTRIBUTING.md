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

- **nixfmt**: formatting
- **deadnix**: unused code detection
- **nil**: Nix language diagnostics
- **statix**: anti-pattern linting

All tools used in the project, including `just`, are provided by the dev shell. We strongly recommend using it to ensure your environment matches CI:

```sh
nix develop
```

If you use [direnv](https://direnv.net/), the `.envrc` is already set up — just run `direnv allow` and the environment will activate automatically when you enter the directory.

The dev shell also installs pre-commit hooks that automatically run nixfmt, deadnix, nil, and statix on every commit, catching issues before they reach CI.

## Testing

The minimum requirement for a PR to be considered for merge is that the following just recipes pass:

```sh
just check
just build
```

This runs all linters, eval tests, and builds the default package. If your change affects the service module or build library, also verify that the example flake still evaluates correctly.

## LLM and AI Agent Usage

This project does not accept contributions from AI bots. All PRs that appear to come from such accounts will be closed and potentially banned if configured as an obstacle to the development of the project.

Patches created by LLMs and AI agents are also viewed with suspicion.
All LLM generated patches MUST have text in the git log and in the PR description that indicates the
patch was created using an LLM. First time contributions by way of LLM generated patches are not welcome.

Thanks for your time, please be respectful of ours.
