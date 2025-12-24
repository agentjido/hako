# Contributing to Hako

Welcome to the Hako contributor's guide! We're excited that you're interested in contributing to Hako, a filesystem abstraction library for Elixir.

## Getting Started

### Development Environment

1. **Elixir Version Requirements**
   - Hako requires Elixir ~> 1.11
   - We recommend using asdf or similar version manager

2. **Initial Setup**
   ```bash
   # Clone the repository
   git clone https://github.com/agentjido/hako.git
   cd hako

   # Install dependencies
   mix deps.get

   # Run tests to verify your setup
   mix test
   ```

3. **S3 Testing Setup (Optional)**
   ```bash
   # Download Minio for S3 adapter testing
   MIX_ENV=test mix minio_server.download --arch darwin-arm64 --version latest
   ```

4. **Quality Checks**
   ```bash
   # Run the full quality check suite
   mix quality

   # Or individual checks
   mix format                    # Format code
   mix compile --warnings-as-errors  # Check compilation
   mix dialyzer                  # Type checking
   mix credo                     # Static analysis
   ```

## Code Organization

### Project Structure
```
.
├── lib/
│   ├── hako/
│   │   ├── adapter/       # Filesystem adapters
│   │   │   ├── local.ex   # Local filesystem
│   │   │   ├── in_memory.ex # In-memory storage
│   │   │   ├── ets.ex     # ETS-backed storage
│   │   │   ├── s3.ex      # AWS S3 / Minio
│   │   │   ├── git.ex     # Git repositories
│   │   │   └── github.ex  # GitHub API
│   │   ├── errors.ex      # Error types
│   │   ├── filesystem.ex  # Filesystem behaviour
│   │   ├── stat/          # File stat structures
│   │   └── visibility.ex  # Visibility handling
│   └── hako.ex           # Main entry point
├── test/
│   ├── hako/
│   │   └── adapter/      # Adapter tests
│   ├── support/          # Test helpers
│   └── test_helper.exs
└── mix.exs
```

### Core Components
- **Adapters**: Backend implementations for different storage systems
- **Filesystem**: The behaviour that all adapters implement
- **Stat**: File metadata structures
- **Visibility**: File permission handling

## Development Guidelines

### Code Style

1. **Formatting**
   - Run `mix format` before committing
   - Follow standard Elixir style guide
   - Use `snake_case` for functions and variables
   - Use `PascalCase` for module names

2. **Documentation**
   - Add `@moduledoc` to every module
   - Document all public functions with `@doc`
   - Include examples when helpful
   - Use doctests for simple examples

3. **Type Specifications**
   ```elixir
   @type filesystem :: {module(), Hako.Adapter.config()}

   @spec read(filesystem, Path.t(), keyword()) :: {:ok, binary} | {:error, term}
   def read({adapter, config}, path, opts \\ []) do
     # Implementation
   end
   ```

### Testing

1. **Test Organization**
   ```elixir
   defmodule Hako.Adapter.LocalTest do
     use ExUnit.Case, async: true

     describe "read/2" do
       test "reads file contents" do
         # Test implementation
       end

       test "returns error for missing file" do
         # Error case testing
       end
     end
   end
   ```

2. **Coverage Requirements**
   - Maintain high test coverage
   - Test both success and error paths
   - Test async behavior where applicable

3. **Running Tests**
   ```bash
   # Run full test suite
   mix test

   # Run with coverage
   mix coveralls

   # Run specific test file
   mix test test/hako/adapter/local_test.exs

   # Include S3 tests (requires Minio)
   mix test --include s3

   # Include integration tests
   mix test --include integration
   ```

### Error Handling

1. **Use With Patterns**
   ```elixir
   def copy(filesystem, source, destination, opts) do
     with {:ok, normalized_source} <- Hako.RelativePath.normalize(source),
          {:ok, normalized_dest} <- Hako.RelativePath.normalize(destination) do
       adapter.copy(config, normalized_source, normalized_dest, opts)
     end
   end
   ```

2. **Return Values**
   - Use tagged tuples: `{:ok, result}` or `{:error, reason}`
   - Create specific error types for different failures
   - Avoid silent failures
   - Document error conditions

## Git Workflow

### Commit Message Format

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | Description |
|------|-------------|
| `feat` | A new feature |
| `fix` | A bug fix |
| `docs` | Documentation only changes |
| `style` | Changes that don't affect code meaning |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvement |
| `test` | Adding or correcting tests |
| `chore` | Changes to build process or auxiliary tools |
| `ci` | CI configuration changes |

### Examples

```bash
# Feature
git commit -m "feat(git): add revision history support"

# Bug fix
git commit -m "fix(s3): resolve timeout in streaming operations"

# Breaking change
git commit -m "feat(api)!: change filesystem return type"
```

## Pull Request Process

1. **Before Submitting**
   - Run the full quality check suite: `mix quality`
   - Ensure all tests pass
   - Update documentation if needed
   - Add tests for new functionality

2. **PR Guidelines**
   - Create a feature branch from `main`
   - Use descriptive commit messages following conventional commits
   - Reference any related issues
   - Keep changes focused and atomic

3. **Review Process**
   - PRs require at least one review
   - Address all review comments
   - Maintain a clean commit history
   - Update your branch if needed

## Release Process

Releases are handled automatically by maintainers. Contributors should:

1. **Use Conventional Commits** - Your commit messages determine changelog entries
2. **Do NOT edit `CHANGELOG.md`** - It is auto-generated during releases
3. **Documentation** - Update guides and docstrings as needed

## Additional Resources

- [Hex Documentation](https://hexdocs.pm/hako)
- [GitHub Issues](https://github.com/agentjido/hako/issues)
- [AgentJido Discord](https://agentjido.xyz/discord)

## Questions or Problems?

If you have questions about contributing:
- Open a GitHub Issue
- Join our Discord community
- Check existing issues and documentation

Thank you for contributing to Hako!
