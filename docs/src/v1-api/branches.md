# Branches

## `main` - this is where development happens; it can **break**!

As we strive for trunk-based development and smaller commits, testing each
subsystem on each supported system for each commit is expensive in terms of
computing resources, so we only run CI checks on `x86_64-linux` here.

Another reason is that, as of time of writing, you need shell access
to a target, i.e. `aarch64-darwin` machine, to update platform-specific lock
files. We hope to allow at least remote builders here soon.

## `stable` - still no warranties, but some best-effort promises ;)

Each commit here should include a changelog since the last commit, and pass all CI jobs
on all platforms, before being tagged. Tagging it will then publish a GitHub release.

A staging branch may be used to prepare the changelog and fixes for non `x86_64-linux`
when needed, but it should be merged into `main` before tagging and cherry-picking
that commit into `stable`.

The changelog contains a list of breaking changes since the last release.

