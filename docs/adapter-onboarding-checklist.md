# Adapter Onboarding Checklist

Use this checklist when adding a new `Jido.VFS.Adapter.*` module or when changing adapter metadata semantics.

## 1. Metadata callbacks (required)

- Implement `unsupported_operations/0`.
- Implement `versioning_module/0`.
- Return stable values:
  - `unsupported_operations/0` returns a list of operation atoms.
  - `versioning_module/0` returns a module that implements `Jido.VFS.Adapter.Versioning`, or `nil`.

## 2. Error semantics

- Public API paths must return `:ok`, `{:ok, value}`, or `{:error, %Jido.VFS.Errors.*{}}`.
- Unsupported paths must return `%Jido.VFS.Errors.UnsupportedOperation{operation, adapter}`.
- Map backend/platform-specific failures to typed errors (`FileNotFound`, `PermissionDenied`, `AdapterError`, etc.).

## 3. Contract and metadata tests

- Add/extend adapter tests for happy paths and representative failure paths.
- Add/extend tests that exercise metadata callbacks through `Jido.VFS.supports?/2` and versioning calls.
- Ensure the adapter remains covered by metadata contract tests in `test/jido_vfs/adapter/metadata_contract_test.exs`.

## 4. Docs and discoverability

- Update `README.md` and/or `CONTRIBUTING.md` if adapter behavior or prerequisites changed.
- Keep dependency examples and adapter capability notes aligned with the implementation.

## 5. Release gates

- Run `mix test`.
- Run `mix quality`.
