# Hako

![Elixir CI](https://github.com/agentjido/hako/workflows/Elixir%20CI/badge.svg)  
[Hex Package](https://hex.pm/packages/hako) | 
[Online Documentation](https://hexdocs.pm/hako).

<!-- MDOC !-->

Hako is a filesystem abstraction for elixir providing a unified interface over many implementations. It allows you to swap out filesystems on the fly without needing to rewrite all of your application code in the process. It can eliminate vendor-lock in, reduce technical debt, and improve the testability of your code.

## Examples

```elixir
defmodule LocalFileSystem do
  use Hako.Filesystem,
    adapter: Hako.Adapter.Local,
    prefix: prefix
end

LocalFileSystem.write("test.txt", "Hello World")
{:ok, "Hello World"} = LocalFileSystem.read("test.txt")
```

### Git Adapter with Versioning

The Git adapter provides version-controlled filesystem operations:

```elixir
# Configure Git filesystem with manual commits
{_module, filesystem} = Hako.Adapter.Git.configure(
  path: "/path/to/repo",
  mode: :manual,
  author: [name: "Bot", email: "bot@example.com"]
)

# Write files and commit manually
Hako.write(filesystem, "document.txt", "Version 1")
Hako.commit(filesystem, "Add initial document")

# View revision history
{:ok, revisions} = Hako.revisions(filesystem, "document.txt")

# Read historical versions
{:ok, old_content} = Hako.read_revision(filesystem, "document.txt", revision_sha)

# Auto-commit mode
{_module, auto_fs} = Hako.Adapter.Git.configure(path: "/repo", mode: :auto)
Hako.write(auto_fs, "file.txt", "content")  # Automatically committed
```

### GitHub Adapter

The GitHub adapter allows you to interact with GitHub repositories as a virtual filesystem:

```elixir
# Configure GitHub filesystem for public repo (read-only)
{_module, github_fs} = Hako.Adapter.GitHub.configure(
  owner: "octocat",
  repo: "Hello-World",
  ref: "main"
)

# Read files from GitHub
{:ok, content} = Hako.read(github_fs, "README.md")
{:ok, files} = Hako.list_contents(github_fs, "")

# Configure with authentication for write operations
{_module, auth_fs} = Hako.Adapter.GitHub.configure(
  owner: "your-username",
  repo: "your-repo",
  ref: "main",
  auth: %{access_token: "your_github_token"},
  commit_info: %{
    message: "Update via Hako",
    committer: %{name: "Your Name", email: "your@email.com"},
    author: %{name: "Your Name", email: "your@email.com"}
  }
)

# Write files (creates commits)
Hako.write(auth_fs, "new_file.txt", "Hello GitHub!", 
            message: "Add new file via Hako")

# Copy and move files
Hako.copy(auth_fs, "source.txt", "dest.txt", 
           message: "Copy file via Hako")
Hako.move(auth_fs, "old_name.txt", "new_name.txt", 
           message: "Rename file via Hako")

# Check file existence
{:ok, :exists} = Hako.file_exists(auth_fs, "README.md")
{:ok, :missing} = Hako.file_exists(auth_fs, "nonexistent.txt")
```

## Visibility

Hako does by default only deal with a limited, but portable, set of visibility permissions:

- `:public`
- `:private`

For more details and how to apply custom visibility permissions take a look at `Hako.Visibility`

## Options

  The following write options apply to all adapters:

  * `:visibility` - Set the visibility for files written
  * `:directory_visibility` - Set the visibility for directories written (if applicable)

<!-- MDOC !-->

## Installation

The package can be installed by adding `hako` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hako, "~> 1.0"}
  ]
end
```
