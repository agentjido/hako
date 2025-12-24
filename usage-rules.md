# Hako Usage Rules

Filesystem abstraction for Elixir with unified interface over multiple backends.

## Filesystem Creation

```elixir
# Direct filesystem configuration
filesystem = Hako.Adapter.Local.configure(prefix: "/home/user/storage")

# Module-based filesystem (recommended for reuse)
defmodule MyStorage do
  use Hako.Filesystem,
    adapter: Hako.Adapter.Local,
    prefix: "/home/user/storage"
end
```

## Basic Operations

```elixir
# Write
:ok = Hako.write(filesystem, "test.txt", "Hello World")

# Read
{:ok, content} = Hako.read(filesystem, "test.txt")

# Delete
:ok = Hako.delete(filesystem, "test.txt")

# Copy
:ok = Hako.copy(filesystem, "source.txt", "dest.txt")

# Move
:ok = Hako.move(filesystem, "old.txt", "new.txt")

# Check existence
{:ok, :exists} = Hako.file_exists(filesystem, "test.txt")
{:ok, :missing} = Hako.file_exists(filesystem, "nonexistent.txt")

# List contents
{:ok, entries} = Hako.list_contents(filesystem, "subdir/")

# Get file info
{:ok, stat} = Hako.stat(filesystem, "test.txt")
```

## Adapters

### Local Filesystem

```elixir
filesystem = Hako.Adapter.Local.configure(prefix: "/path/to/storage")
```

### In-Memory (Testing)

```elixir
filesystem = Hako.Adapter.InMemory.configure(name: :test_fs)
```

### ETS-Backed

```elixir
filesystem = Hako.Adapter.ETS.configure(name: :persistent_fs)
```

### S3 / Minio

```elixir
filesystem = Hako.Adapter.S3.configure(
  bucket: "my-bucket",
  prefix: "uploads/",
  access_key_id: "...",
  secret_access_key: "..."
)
```

### Git Repository

```elixir
# Manual commit mode
filesystem = Hako.Adapter.Git.configure(
  path: "/path/to/repo",
  mode: :manual,
  author: [name: "Bot", email: "bot@example.com"]
)

# Auto-commit mode
filesystem = Hako.Adapter.Git.configure(
  path: "/path/to/repo",
  mode: :auto
)
```

### GitHub API

```elixir
# Read-only access
filesystem = Hako.Adapter.GitHub.configure(
  owner: "octocat",
  repo: "Hello-World",
  ref: "main"
)

# Authenticated access for writes
filesystem = Hako.Adapter.GitHub.configure(
  owner: "username",
  repo: "repo-name",
  ref: "main",
  auth: %{access_token: "ghp_..."},
  commit_info: %{
    message: "Update via Hako",
    committer: %{name: "Name", email: "email@example.com"},
    author: %{name: "Name", email: "email@example.com"}
  }
)
```

## Versioning (Git, ETS, InMemory)

```elixir
# Commit changes (manual mode)
Hako.write(filesystem, "file.txt", "content")
:ok = Hako.commit(filesystem, "Add new file")

# List revisions
{:ok, revisions} = Hako.revisions(filesystem, "file.txt")

# Read historical version
{:ok, old_content} = Hako.read_revision(filesystem, "file.txt", revision_id)

# Rollback
:ok = Hako.rollback(filesystem, revision_id)
```

## Streaming

```elixir
# Read stream
{:ok, stream} = Hako.read_stream(filesystem, "large-file.bin", chunk_size: 65536)
Enum.each(stream, fn chunk -> process(chunk) end)

# Write stream
{:ok, stream} = Hako.write_stream(filesystem, "output.bin")
data |> Stream.into(stream) |> Stream.run()
```

## Cross-Filesystem Copy

```elixir
source_fs = Hako.Adapter.Local.configure(prefix: "/source")
dest_fs = Hako.Adapter.S3.configure(bucket: "dest-bucket")

:ok = Hako.copy_between_filesystem(
  {source_fs, "file.txt"},
  {dest_fs, "uploaded.txt"}
)
```

## Visibility

```elixir
# Set file visibility
:ok = Hako.set_visibility(filesystem, "file.txt", :public)
:ok = Hako.set_visibility(filesystem, "file.txt", :private)

# Get visibility
{:ok, :public} = Hako.visibility(filesystem, "file.txt")

# Write with visibility
:ok = Hako.write(filesystem, "file.txt", "content", visibility: :public)
```

## Directories

```elixir
# Create directory
:ok = Hako.create_directory(filesystem, "new-folder")

# Delete directory
:ok = Hako.delete_directory(filesystem, "old-folder")

# Clear all contents
:ok = Hako.clear(filesystem)
```

## Error Handling

```elixir
case Hako.read(filesystem, "file.txt") do
  {:ok, content} -> process(content)
  {:error, %Hako.Errors.FileNotFound{}} -> handle_missing()
  {:error, %Hako.Errors.PathTraversal{}} -> handle_security_error()
  {:error, reason} -> handle_error(reason)
end
```

## Anti-Patterns

**❌ Avoid:**
- Absolute paths: `Hako.read(fs, "/etc/passwd")`
- Path traversal: `Hako.read(fs, "../../../etc/passwd")`
- Ignoring errors: `Hako.write(fs, path, content)`
- Direct file operations: `File.read!(path)`

**✅ Use:**
- Relative paths: `Hako.read(fs, "documents/file.txt")`
- Error handling: `case Hako.read(...) do`
- Filesystem abstraction for all file operations
- Module-based filesystems for reusable configurations

## Testing

```elixir
# Use InMemory adapter for tests
setup do
  filesystem = Hako.Adapter.InMemory.configure(name: :test_fs)
  {:ok, filesystem: filesystem}
end

test "writes and reads file", %{filesystem: fs} do
  :ok = Hako.write(fs, "test.txt", "hello")
  assert {:ok, "hello"} = Hako.read(fs, "test.txt")
end
```
