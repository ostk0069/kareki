# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

## 0.1.0

Initial release.

- Rules: `unused_element`, `unused_file`, `unused_pub_dependency`.
- Multi-package workspaces via `melos.yaml` / pub workspaces.
- Built-in presets: `freezed`, `json_serializable`, `riverpod`, `auto_route`, `go_router`, `drift`, `hive`, `meta`.
- Configuration via `kareki-config.yaml` with full override and custom preset support.
- CLI: `dart run kareki` with `--format`, `--packages`, `--rule`, `--strict`.
- Dart `>=3.10.0`, analyzer `^9.0.0`.
