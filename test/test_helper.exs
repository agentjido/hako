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

unless minio_available? do
  IO.puts("\n⚠️  Minio not available - S3 tests will be skipped")
  ExUnit.configure(exclude: [:s3])
end

ExUnit.start(capture_log: true)
