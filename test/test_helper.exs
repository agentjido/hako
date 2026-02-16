# Only start Minio if the binaries are available
minio_available? =
  try do
    # Capture stdio to suppress minio's JSON output
    ExUnit.CaptureIO.capture_io(fn ->
      {:ok, _} = JidoVfsTest.Minio.start_link()
      :ok = JidoVfsTest.Minio.wait_for_ready()
      JidoVfsTest.Minio.initialize_bucket("default")
    end)

    true
  rescue
    RuntimeError -> false
  end

# Check if git is configured properly for tests
git_available? =
  case System.cmd("git", ["config", "user.name"], stderr_to_stdout: true) do
    {name, 0} when byte_size(name) > 0 -> true
    _ -> false
  end

# Expose probe results to test modules for deterministic compile-time tagging.
Application.put_env(:jido_vfs, :minio_available, minio_available?)
Application.put_env(:jido_vfs, :git_available, git_available?)

# Build exclusion list
excludes = [:integration]
excludes = if minio_available?, do: excludes, else: [:s3 | excludes]
excludes = if git_available?, do: excludes, else: [:git | excludes]

unless minio_available? do
  IO.puts("\n⚠️  Minio not available - S3 tests will be skipped")
end

unless git_available? do
  IO.puts("\n⚠️  Git user not configured - Git tests will be skipped")
end

IO.puts("\n📋 To run integration tests: mix test --include integration")
IO.puts("📋 To run git tests: mix test --include git")

ExUnit.start(capture_log: true, exclude: excludes)
