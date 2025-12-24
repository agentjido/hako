# Hako

[![CI](https://github.com/agentjido/hako/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/hako/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/hako.svg)](https://hex.pm/packages/hako)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/hako)

<!-- MDOC !-->

Hako is a filesystem abstraction for Elixir providing a unified interface over many storage backends. It allows you to swap out filesystems on the fly without needing to rewrite your application code. Eliminate vendor lock-in, reduce technical debt, and improve testability.

## Features

- **Unified API** - Same operations work across all adapters
- **Multiple Backends** - Local, S3, Git, GitHub, ETS, and InMemory storage
- **Version Control** - Git, ETS, and InMemory adapters support versioning
- **Streaming** - Efficient handling of large files
- **Cross-Filesystem Operations** - Copy files between different storage backends
- **Visibility Controls** - Public/private file permissions

## Adapters

| Adapter | Use Case | Features |
|---------|----------|----------|
| `Hako.Adapter.Local` | Local filesystem | Standard file operations, streaming |
| `Hako.Adapter.S3` | AWS S3 / Minio | Cloud storage, streaming, presigned URLs |
| `Hako.Adapter.Git` | Git repositories | Version control, commit history, rollback |
| `Hako.Adapter.GitHub` | GitHub API | Remote repo access, commits via API |
| `Hako.Adapter.ETS` | ETS tables | Fast in-memory with versioning |
| `Hako.Adapter.InMemory` | Testing | Ephemeral storage with versioning |

## Quick Start

```elixir
# Direct filesystem configuration
filesystem = Hako.Adapter.Local.configure(prefix: "/home/user/storage")

# Write and read files
:ok = Hako.write(filesystem, "test.txt", "Hello World")
{:ok, "Hello World"} = Hako.read(filesystem, "test.txt")

# Module-based filesystem (recommended for reuse)
defmodule MyStorage do
  use Hako.Filesystem,
    adapter: Hako.Adapter.Local,
    prefix: "/home/user/storage"
end

MyStorage.write("test.txt", "Hello World")
{:ok, "Hello World"} = MyStorage.read("test.txt")
```

## Local Adapter

The Local adapter provides standard filesystem operations:

```elixir
filesystem = Hako.Adapter.Local.configure(prefix: "/path/to/storage")

# Basic operations
:ok = Hako.write(filesystem, "file.txt", "content")
{:ok, content} = Hako.read(filesystem, "file.txt")
:ok = Hako.delete(filesystem, "file.txt")

# Copy and move
:ok = Hako.copy(filesystem, "source.txt", "dest.txt")
:ok = Hako.move(filesystem, "old.txt", "new.txt")

# Directory operations
:ok = Hako.create_directory(filesystem, "new-folder")
{:ok, entries} = Hako.list_contents(filesystem, "folder/")
:ok = Hako.delete_directory(filesystem, "old-folder")

# File info
{:ok, stat} = Hako.stat(filesystem, "file.txt")
{:ok, :exists} = Hako.file_exists(filesystem, "file.txt")
```

## S3 Adapter

The S3 adapter works with AWS S3, Minio, and S3-compatible storage:

```elixir
# Configure S3 filesystem
filesystem = Hako.Adapter.S3.configure(
  bucket: "my-bucket",
  prefix: "uploads/",
  region: "us-east-1"
)

# For Minio or custom S3-compatible storage
filesystem = Hako.Adapter.S3.configure(
  bucket: "my-bucket",
  host: "localhost",
  port: 9000,
  scheme: "http://",
  access_key_id: "minioadmin",
  secret_access_key: "minioadmin"
)

# All standard operations work
:ok = Hako.write(filesystem, "document.pdf", pdf_binary)
{:ok, content} = Hako.read(filesystem, "document.pdf")

# Streaming for large files
{:ok, stream} = Hako.read_stream(filesystem, "large-file.bin", chunk_size: 65536)
Enum.each(stream, fn chunk -> process(chunk) end)
```

## Git Adapter

The Git adapter provides version-controlled filesystem operations:

```elixir
# Manual commit mode - you control when commits happen
filesystem = Hako.Adapter.Git.configure(
  path: "/path/to/repo",
  mode: :manual,
  author: [name: "Bot", email: "bot@example.com"]
)

# Write files and commit manually
Hako.write(filesystem, "document.txt", "Version 1")
Hako.write(filesystem, "notes.txt", "Some notes")
:ok = Hako.commit(filesystem, "Add initial documents")

# Auto-commit mode - each write creates a commit
filesystem = Hako.Adapter.Git.configure(
  path: "/path/to/repo",
  mode: :auto
)
Hako.write(filesystem, "file.txt", "content")  # Automatically committed

# View revision history
{:ok, revisions} = Hako.revisions(filesystem, "document.txt")

# Read historical versions
{:ok, old_content} = Hako.read_revision(filesystem, "document.txt", revision_sha)

# Rollback to a previous revision
:ok = Hako.rollback(filesystem, revision_sha)
```

## GitHub Adapter

The GitHub adapter allows you to interact with GitHub repositories as a virtual filesystem:

```elixir
# Read-only access to public repos
filesystem = Hako.Adapter.GitHub.configure(
  owner: "octocat",
  repo: "Hello-World",
  ref: "main"
)

{:ok, content} = Hako.read(filesystem, "README.md")
{:ok, files} = Hako.list_contents(filesystem, "src/")

# Authenticated access for write operations
filesystem = Hako.Adapter.GitHub.configure(
  owner: "your-username",
  repo: "your-repo",
  ref: "main",
  auth: %{access_token: "ghp_your_token"},
  commit_info: %{
    message: "Update via Hako",
    committer: %{name: "Your Name", email: "you@example.com"},
    author: %{name: "Your Name", email: "you@example.com"}
  }
)

# Write files (creates commits)
Hako.write(filesystem, "new_file.txt", "Hello GitHub!", 
  message: "Add new file via Hako")
```

## ETS and InMemory Adapters

These adapters are ideal for testing and caching:

```elixir
# ETS adapter - persists to ETS table
filesystem = Hako.Adapter.ETS.configure(name: :my_cache)

# InMemory adapter - ephemeral storage
filesystem = Hako.Adapter.InMemory.configure(name: :test_fs)

# Both support versioning
Hako.write(filesystem, "file.txt", "v1")
:ok = Hako.commit(filesystem, "Version 1")

Hako.write(filesystem, "file.txt", "v2")
:ok = Hako.commit(filesystem, "Version 2")

{:ok, revisions} = Hako.revisions(filesystem, "file.txt")
{:ok, "v1"} = Hako.read_revision(filesystem, "file.txt", first_revision_id)
```

## Cross-Filesystem Operations

Copy files between different storage backends:

```elixir
local_fs = Hako.Adapter.Local.configure(prefix: "/local/storage")
s3_fs = Hako.Adapter.S3.configure(bucket: "my-bucket")

# Copy from local to S3
:ok = Hako.copy_between_filesystem(
  {local_fs, "document.pdf"},
  {s3_fs, "uploads/document.pdf"}
)

# Copy from S3 to local
:ok = Hako.copy_between_filesystem(
  {s3_fs, "backup.zip"},
  {local_fs, "downloads/backup.zip"}
)
```

## Streaming

Efficiently handle large files with streaming:

```elixir
# Read stream
{:ok, stream} = Hako.read_stream(filesystem, "large-file.bin", chunk_size: 65536)
Enum.each(stream, fn chunk -> process(chunk) end)

# Write stream
{:ok, stream} = Hako.write_stream(filesystem, "output.bin")
data |> Stream.into(stream) |> Stream.run()
```

## Visibility

Control file permissions with visibility settings:

```elixir
# Write with visibility
:ok = Hako.write(filesystem, "public-file.txt", "content", visibility: :public)
:ok = Hako.write(filesystem, "private-file.txt", "secret", visibility: :private)

# Get/set visibility
{:ok, :public} = Hako.visibility(filesystem, "public-file.txt")
:ok = Hako.set_visibility(filesystem, "file.txt", :private)
```

<!-- MDOC !-->

## Installation

Add `hako` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hako, "~> 1.0"}
  ]
end
```

## Documentation

Full documentation is available at [HexDocs](https://hexdocs.pm/hako).

## License

Apache-2.0 - see [LICENSE.md](LICENSE.md) for details.
