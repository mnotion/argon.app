# Argon versioning

This folder owns version-number parsing, comparison and latest-release metadata lookup. It is intentionally independent from package download and installation logic.

## Current version

The application version is defined by the CMake project version. The current baseline is `0.1.0`; `AppServices.version` reads the runtime application version set in `main.cpp`.

## Version rules

- Exactly `MAJOR.MINOR.PATCH`, e.g. `1.4.2`.
- Every component is a non-negative integer.
- Leading zeros are rejected unless the component is exactly `0`.
- Versions are compared component-by-component as numbers, not as strings.
- Prerelease suffixes such as `-dev` are deliberately unsupported in this initial three-component system.

## Release metadata

`ReleaseMetadataService` reads `latest.json` asynchronously using Qt Network. The endpoint defaults to:

`https://raw.githubusercontent.com/ananas123123/argon.updater/rel-config/latest.json`

Set `ARGON_LATEST_JSON_URL` to override that endpoint during development. Plain HTTP is accepted only for loopback test servers; remote metadata must use HTTPS.

The service validates the JSON schema and version fields before comparing versions. It does not download or install application packages.

**Private repository caveat:** an installed app cannot anonymously read a private GitHub repository. The default request will fail until the metadata is served through an endpoint accessible to the app's intended users. No GitHub token should be embedded in Argon.

## Logic tests

Configure with `-DARGON_BUILD_VERSIONING_TESTS=ON`, build the `ArgonVersioningTests` target and run CTest. These tests validate parsing, ordering and release-metadata schema without network access.
