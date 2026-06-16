# Release Flow

TRAX releases are driven by `scripts/release.sh` and tracked through a resumable local state file at
`.local/release/state.env`.

## Version Source Of Truth

- `VERSION` stores the current release version as semantic version text such as `0.2.0`.
- The release tag is derived as `v$(VERSION)`.

## Release Image Tags

Each release publishes daemon and CLI images with three tags:

- `latest`
- `$(VERSION)`
- `$(HASH_TAG)` where `HASH_TAG` is the full `git rev-parse HEAD` commit hash

The release flow still keeps the normal branch/hash tags available for non-release builds.

## Linux Build Path

`make build-daemons` and `make build-clis` do **not** compile host binaries directly. They run the
same containerized Go-builder pattern used in the earlier daemons2 setup, write Linux artifacts
into `bin/`, and then build runtime images from those binaries.

## Commands

```bash
make release
make release-resume
make release-status
make release-reset
```

## Release Sequence

`make release` runs these steps and records completion after each one:

1. validate prerequisites, GitHub auth, semver, branch state, and clean worktree
2. run `make test-unit`
3. run `make bi`, `make tag-release-images`, and `make push-release-images`
4. create the annotated git tag `v$(VERSION)` if it does not already exist on the release commit
5. push the branch and tag to `origin`
6. create a GitHub release with generated notes
7. ask whether to bump `patch`, `minor`, `major`, or `none` for the next version
8. when a bump is chosen, update `VERSION`, commit it, and push the branch

If any step fails, fix the cause and run `make release-resume`.

## Notes

- `gh auth status` must succeed before the release can proceed.
- releases are allowed only from `main`.
- local `main` must be clean and fully synchronized with `origin/main`; ahead, behind, or diverged
  states are rejected before any release step starts.
- the Linux binary builder defaults to `xshyft/golang-builder:1.24.latest` through the Makefile
- The release script is intentionally fail-fast; it does not guess around dirty state, detached
  HEAD, or mismatched release metadata.
- `make release-reset` only removes the local resumable state file. It does **not** undo git tags,
  pushed refs, images, or GitHub releases that may already exist.
