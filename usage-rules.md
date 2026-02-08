# Jido.VFS Usage Rules

Filesystem abstraction for Elixir with unified interface over multiple backends.

## Filesystem Creation

```elixir
# Direct filesystem configuration
filesystem = Jido.VFS.Adapter.Local.configure(prefix: "/home/user/storage")

# Module-based filesystem (recommended for reuse)
defmodule MyStorage do
  use Jido.VFS.Filesystem,
    adapter: Jido.VFS.Adapter.Local,
    prefix: "/home/user/storage"
end
```

## Basic Operations

```elixir
# Write
:ok = Jido.VFS.write(filesystem, "test.txt", "Hello World")

# Read
{:ok, content} = Jido.VFS.read(filesystem, "test.txt")

# Delete
:ok = Jido.VFS.delete(filesystem, "test.txt")

# Copy
:ok = Jido.VFS.copy(filesystem, "source.txt", "dest.txt")

# Move
:ok = Jido.VFS.move(filesystem, "old.txt", "new.txt")

# Check existence
{:ok, :exists} = Jido.VFS.file_exists(filesystem, "test.txt")
{:ok, :missing} = Jido.VFS.file_exists(filesystem, "nonexistent.txt")

# List contents
{:ok, entries} = Jido.VFS.list_contents(filesystem, "subdir/")

# Get file info
{:ok, stat} = Jido.VFS.stat(filesystem, "test.txt")
```

## Adapters

### Local Filesystem

```elixir
filesystem = Jido.VFS.Adapter.Local.configure(prefix: "/path/to/storage")
```

### In-Memory (Testing)

```elixir
filesystem = Jido.VFS.Adapter.InMemory.configure(name: :test_fs)
```

### ETS-Backed

```elixir
filesystem = Jido.VFS.Adapter.ETS.configure(name: :persistent_fs)
```

### S3 / Minio

```elixir
filesystem = Jido.VFS.Adapter.S3.configure(
  bucket: "my-bucket",
  prefix: "uploads/",
  access_key_id: "...",
  secret_access_key: "..."
)
```

### Git Repository

```elixir
# Manual commit mode
filesystem = Jido.VFS.Adapter.Git.configure(
  path: "/path/to/repo",
  mode: :manual,
  author: [name: "Bot", email: "bot@example.com"]
)

# Auto-commit mode
filesystem = Jido.VFS.Adapter.Git.configure(
  path: "/path/to/repo",
  mode: :auto
)
```

### GitHub API

```elixir
# Read-only access
filesystem = Jido.VFS.Adapter.GitHub.configure(
  owner: "octocat",
  repo: "Hello-World",
  ref: "main"
)

# Authenticated access for writes
filesystem = Jido.VFS.Adapter.GitHub.configure(
  owner: "username",
  repo: "repo-name",
  ref: "main",
  auth: %{access_token: "ghp_..."},
  commit_info: %{
    message: "Update via Jido.VFS",
    committer: %{name: "Name", email: "email@example.com"},
    author: %{name: "Name", email: "email@example.com"}
  }
)
```

## Versioning (Git, ETS, InMemory)

```elixir
# Commit changes (manual mode)
Jido.VFS.write(filesystem, "file.txt", "content")
:ok = Jido.VFS.commit(filesystem, "Add new file")

# List revisions
{:ok, revisions} = Jido.VFS.revisions(filesystem, "file.txt")

# Read historical version
{:ok, old_content} = Jido.VFS.read_revision(filesystem, "file.txt", revision_id)

# Rollback
:ok = Jido.VFS.rollback(filesystem, revision_id)
```

## Streaming

```elixir
# Read stream
{:ok, stream} = Jido.VFS.read_stream(filesystem, "large-file.bin", chunk_size: 65536)
Enum.each(stream, fn chunk -> process(chunk) end)

# Write stream
{:ok, stream} = Jido.VFS.write_stream(filesystem, "output.bin")
data |> Stream.into(stream) |> Stream.run()
```

## Cross-Filesystem Copy

```elixir
source_fs = Jido.VFS.Adapter.Local.configure(prefix: "/source")
dest_fs = Jido.VFS.Adapter.S3.configure(bucket: "dest-bucket")

:ok = Jido.VFS.copy_between_filesystem(
  {source_fs, "file.txt"},
  {dest_fs, "uploaded.txt"}
)
```

## Visibility

```elixir
# Set file visibility
:ok = Jido.VFS.set_visibility(filesystem, "file.txt", :public)
:ok = Jido.VFS.set_visibility(filesystem, "file.txt", :private)

# Get visibility
{:ok, :public} = Jido.VFS.visibility(filesystem, "file.txt")

# Write with visibility
:ok = Jido.VFS.write(filesystem, "file.txt", "content", visibility: :public)
```

## Directories

```elixir
# Create directory
:ok = Jido.VFS.create_directory(filesystem, "new-folder")

# Delete directory
:ok = Jido.VFS.delete_directory(filesystem, "old-folder")

# Clear all contents
:ok = Jido.VFS.clear(filesystem)
```

## Error Handling

```elixir
case Jido.VFS.read(filesystem, "file.txt") do
  {:ok, content} -> process(content)
  {:error, %Jido.VFS.Errors.FileNotFound{}} -> handle_missing()
  {:error, %Jido.VFS.Errors.PathTraversal{}} -> handle_security_error()
  {:error, reason} -> handle_error(reason)
end
```

## Anti-Patterns

**❌ Avoid:**
- Absolute paths: `Jido.VFS.read(fs, "/etc/passwd")`
- Path traversal: `Jido.VFS.read(fs, "../../../etc/passwd")`
- Ignoring errors: `Jido.VFS.write(fs, path, content)`
- Direct file operations: `File.read!(path)`

**✅ Use:**
- Relative paths: `Jido.VFS.read(fs, "documents/file.txt")`
- Error handling: `case Jido.VFS.read(...) do`
- Filesystem abstraction for all file operations
- Module-based filesystems for reusable configurations

## Testing

```elixir
# Use InMemory adapter for tests
setup do
  filesystem = Jido.VFS.Adapter.InMemory.configure(name: :test_fs)
  {:ok, filesystem: filesystem}
end

test "writes and reads file", %{filesystem: fs} do
  :ok = Jido.VFS.write(fs, "test.txt", "hello")
  assert {:ok, "hello"} = Jido.VFS.read(fs, "test.txt")
end
```
