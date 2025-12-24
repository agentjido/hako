# Only start Minio if the binaries are available
minio_available? =
  try do
    # Capture stdio to suppress minio's JSON output
    ExUnit.CaptureIO.capture_io(fn ->
      {:ok, _} = HakoTest.Minio.start_link()
      :ok = HakoTest.Minio.wait_for_ready()
      HakoTest.Minio.initialize_bucket("default")
    end)

    true
  rescue
    RuntimeError -> false
  end

# Build exclusion list
excludes = [:integration]
excludes = if minio_available?, do: excludes, else: [:s3 | excludes]

unless minio_available? do
  IO.puts("\n⚠️  Minio not available - S3 tests will be skipped")
end

IO.puts("\n📋 To run integration tests: mix test --include integration")

ExUnit.start(capture_log: true, exclude: excludes)
