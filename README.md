# Jido.VFS

[![CI](https://github.com/agentjido/jido_vfs/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/jido_vfs/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/jido_vfs.svg)](https://hex.pm/packages/jido_vfs)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/jido_vfs)

<!-- MDOC !-->

Jido.VFS is a filesystem abstraction for Elixir providing a unified interface over many storage backends. It allows you to swap out filesystems on the fly without needing to rewrite your application code. Eliminate vendor lock-in, reduce technical debt, and improve testability.

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
| `Jido.VFS.Adapter.Local` | Local filesystem | Standard file operations, streaming |
| `Jido.VFS.Adapter.S3` | AWS S3 / Minio | Cloud storage, streaming, presigned URLs |
| `Jido.VFS.Adapter.Git` | Git repositories | Version control, commit history, rollback |
| `Jido.VFS.Adapter.GitHub` | GitHub API | Remote repo access, commits via API |
| `Jido.VFS.Adapter.ETS` | ETS tables | Fast in-memory with versioning |
| `Jido.VFS.Adapter.InMemory` | Testing | Ephemeral storage with versioning |

## Quick Start

```elixir
# Direct filesystem configuration
filesystem = Jido.VFS.Adapter.Local.configure(prefix: "/home/user/storage")

# Write and read files
:ok = Jido.VFS.write(filesystem, "test.txt", "Hello World")
{:ok, "Hello World"} = Jido.VFS.read(filesystem, "test.txt")

# Module-based filesystem (recommended for reuse)
defmodule MyStorage do
  use Jido.VFS.Filesystem,
    adapter: Jido.VFS.Adapter.Local,
    prefix: "/home/user/storage"
end

MyStorage.write("test.txt", "Hello World")
{:ok, "Hello World"} = MyStorage.read("test.txt")
```

## Local Adapter

The Local adapter provides standard filesystem operations:

```elixir
filesystem = Jido.VFS.Adapter.Local.configure(prefix: "/path/to/storage")

# Basic operations
:ok = Jido.VFS.write(filesystem, "file.txt", "content")
{:ok, content} = Jido.VFS.read(filesystem, "file.txt")
:ok = Jido.VFS.delete(filesystem, "file.txt")

# Copy and move
:ok = Jido.VFS.copy(filesystem, "source.txt", "dest.txt")
:ok = Jido.VFS.move(filesystem, "old.txt", "new.txt")

# Directory operations
:ok = Jido.VFS.create_directory(filesystem, "new-folder")
{:ok, entries} = Jido.VFS.list_contents(filesystem, "folder/")
:ok = Jido.VFS.delete_directory(filesystem, "old-folder")

# File info
{:ok, stat} = Jido.VFS.stat(filesystem, "file.txt")
{:ok, :exists} = Jido.VFS.file_exists(filesystem, "file.txt")
```

## S3 Adapter

The S3 adapter works with AWS S3, Minio, and S3-compatible storage:

```elixir
# Configure S3 filesystem
filesystem = Jido.VFS.Adapter.S3.configure(
  bucket: "my-bucket",
  prefix: "uploads/",
  region: "us-east-1"
)

# For Minio or custom S3-compatible storage
filesystem = Jido.VFS.Adapter.S3.configure(
  bucket: "my-bucket",
  host: "localhost",
  port: 9000,
  scheme: "http://",
  access_key_id: "minioadmin",
  secret_access_key: "minioadmin"
)

# All standard operations work
:ok = Jido.VFS.write(filesystem, "document.pdf", pdf_binary)
{:ok, content} = Jido.VFS.read(filesystem, "document.pdf")

# Streaming for large files
{:ok, stream} = Jido.VFS.read_stream(filesystem, "large-file.bin", chunk_size: 65536)
Enum.each(stream, fn chunk -> process(chunk) end)
```

## Git Adapter

The Git adapter provides version-controlled filesystem operations:

```elixir
# Manual commit mode - you control when commits happen
filesystem = Jido.VFS.Adapter.Git.configure(
  path: "/path/to/repo",
  mode: :manual,
  author: [name: "Bot", email: "bot@example.com"]
)

# Write files and commit manually
Jido.VFS.write(filesystem, "document.txt", "Version 1")
Jido.VFS.write(filesystem, "notes.txt", "Some notes")
:ok = Jido.VFS.commit(filesystem, "Add initial documents")

# Auto-commit mode - each write creates a commit
filesystem = Jido.VFS.Adapter.Git.configure(
  path: "/path/to/repo",
  mode: :auto
)
Jido.VFS.write(filesystem, "file.txt", "content")  # Automatically committed

# View revision history
{:ok, revisions} = Jido.VFS.revisions(filesystem, "document.txt")

# Read historical versions
{:ok, old_content} = Jido.VFS.read_revision(filesystem, "document.txt", revision_sha)

# Rollback to a previous revision
:ok = Jido.VFS.rollback(filesystem, revision_sha)
```

## GitHub Adapter

The GitHub adapter allows you to interact with GitHub repositories as a virtual filesystem:

```elixir
# Read-only access to public repos
filesystem = Jido.VFS.Adapter.GitHub.configure(
  owner: "octocat",
  repo: "Hello-World",
  ref: "main"
)

{:ok, content} = Jido.VFS.read(filesystem, "README.md")
{:ok, files} = Jido.VFS.list_contents(filesystem, "src/")

# Authenticated access for write operations
filesystem = Jido.VFS.Adapter.GitHub.configure(
  owner: "your-username",
  repo: "your-repo",
  ref: "main",
  auth: %{access_token: "ghp_your_token"},
  commit_info: %{
    message: "Update via Jido.VFS",
    committer: %{name: "Your Name", email: "you@example.com"},
    author: %{name: "Your Name", email: "you@example.com"}
  }
)

# Write files (creates commits)
Jido.VFS.write(filesystem, "new_file.txt", "Hello GitHub!", 
  message: "Add new file via Jido.VFS")
```

## ETS and InMemory Adapters

These adapters are ideal for testing and caching:

```elixir
# ETS adapter - persists to ETS table
filesystem = Jido.VFS.Adapter.ETS.configure(name: :my_cache)

# InMemory adapter - ephemeral storage
filesystem = Jido.VFS.Adapter.InMemory.configure(name: :test_fs)

# Both support versioning
Jido.VFS.write(filesystem, "file.txt", "v1")
:ok = Jido.VFS.commit(filesystem, "Version 1")

Jido.VFS.write(filesystem, "file.txt", "v2")
:ok = Jido.VFS.commit(filesystem, "Version 2")

{:ok, revisions} = Jido.VFS.revisions(filesystem, "file.txt")
{:ok, "v1"} = Jido.VFS.read_revision(filesystem, "file.txt", first_revision_id)
```

## Cross-Filesystem Operations

Copy files between different storage backends:

```elixir
local_fs = Jido.VFS.Adapter.Local.configure(prefix: "/local/storage")
s3_fs = Jido.VFS.Adapter.S3.configure(bucket: "my-bucket")

# Copy from local to S3
:ok = Jido.VFS.copy_between_filesystem(
  {local_fs, "document.pdf"},
  {s3_fs, "uploads/document.pdf"}
)

# Copy from S3 to local
:ok = Jido.VFS.copy_between_filesystem(
  {s3_fs, "backup.zip"},
  {local_fs, "downloads/backup.zip"}
)
```

## Streaming

Efficiently handle large files with streaming:

```elixir
# Read stream
{:ok, stream} = Jido.VFS.read_stream(filesystem, "large-file.bin", chunk_size: 65536)
Enum.each(stream, fn chunk -> process(chunk) end)

# Write stream
{:ok, stream} = Jido.VFS.write_stream(filesystem, "output.bin")
data |> Stream.into(stream) |> Stream.run()
```

## Visibility

Control file permissions with visibility settings:

```elixir
# Write with visibility
:ok = Jido.VFS.write(filesystem, "public-file.txt", "content", visibility: :public)
:ok = Jido.VFS.write(filesystem, "private-file.txt", "secret", visibility: :private)

# Get/set visibility
{:ok, :public} = Jido.VFS.visibility(filesystem, "public-file.txt")
:ok = Jido.VFS.set_visibility(filesystem, "file.txt", :private)
```

<!-- MDOC !-->

## Installation

### Igniter Installation
If your project has [Igniter](https://hexdocs.pm/igniter/readme.html) available, 
you can install Jido VFS using the command 

```bash
mix igniter.install jido_vfs
```

### Manual Installation

Add `jido_vfs` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido_vfs, "~> 1.0"}
  ]
end
```

## Documentation

Full documentation is available at [HexDocs](https://hexdocs.pm/jido_vfs).

## License

Apache-2.0 - see [LICENSE.md](LICENSE.md) for details.
