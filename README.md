<p align="center">
  <picture>
    <source width="600" media="(prefers-color-scheme: dark)" srcset="https://gist.githubusercontent.com/DavHau/755fed3774e89c0b9b8953a0a25309fa/raw/0312cc4f785de36212f4303d23298f07c13549dc/dream2nix-dark.png">
    <source width="600" media="(prefers-color-scheme: light)" srcset="https://gist.githubusercontent.com/DavHau/755fed3774e89c0b9b8953a0a25309fa/raw/e2a12a60ae49aa5eb11b42775abdd1652dbe63c0/dream2nix-01.png">
    <img width="600" alt="dream2nix - A framework for automated nix packaging" src="https://gist.githubusercontent.com/DavHau/755fed3774e89c0b9b8953a0a25309fa/raw/e2a12a60ae49aa5eb11b42775abdd1652dbe63c0/dream2nix-01.png">
  </picture>
  <br>
  Automate reproducible packaging for various language ecosystems
  <br>
  <a href="https://dream2nix.dev/">Documentation</a> |
  <a href="https://github.com/nix-community/dream2nix/tree/main/examples/repo-with-packages">Example Repo</a> |
  <a href="https://github.com/nix-community/dream2nix/tree/main/examples/repo-with-packages-flake">Example Repo Flake</a> |
  <a href="https://github.com/nix-community/dream2nix/tree/main/examples/packages">Example Packages</a>
</p>

!!! warning

    dream2nix is unstable software. While simple UX is one of our main focus points, the APIs  are still under development. Do expect changes that will break your setup.

### legacy dream2nix

Dream2nix is currently in the process of being refactored to make use of drv-parts. Not all features and subsystems are migrated yet. If you prefer continue using the `makeFlakeOutputs` interface, please refer to the [legacy branch](https://github.com/nix-community/dream2nix/tree/legacy) of dream2nix.

### Funding

This project was funded through the [NGI Assure](https://nlnet.nl/assure) Fund, a fund established by [NLnet](https://nlnet.nl/) with financial support from the European Commission's [Next Generation Internet](https://ngi.eu/) programme, under the aegis of DG Communications Networks, Content and Technology under grant agreement No 957073. **Applications are still open, you can [apply today](https://nlnet.nl/propose)**.

If your organization wants to support the project with extra funding in order to add support for more languages or new features, please contact one of the maintainers.

### Documentation

[👉 To the docs](https://dream2nix.dev/guides/getting-started/)

### Presentations

- [👉 2023: dream2nix based on drv-parts](https://www.youtube.com/watch?v=AsCvRZukX0E)
- [👉 2021: Original dream2nix presentation](https://www.youtube.com/watch?v=jqCfHMvCsfQ) (Examples are outdated)

### Get in touch

[👉 matrix chat room](https://matrix.to/#/#dream2nix:nixos.org)

### Contribute

[👉 GitHub repo](https://github.com/nix-community/dream2nix)

[👉 issues](https://github.com/nix-community/dream2nix/issues)


### Goals

dream2nix focuses on the following aspects:

- Modularity
- Customizability
- Maintainability
- Code de-duplication across 2nix solutions
- Common UI across 2nix solutions
- Reduce effort to develop new 2nix solutions
- Exploration and adoption of new nix features
- Simplified updating of packages

The goal of this project is to create a standardized, generic, modular framework for automated packaging solutions, aiming for better flexibility, maintainability and usability.

The intention is to integrate many existing 2nix converters into this framework, thereby improving many of the previously named aspects and providing a unified UX for all 2nix solutions.
