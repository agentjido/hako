# Only start Minio if the binaries are available
minio_available? =
  try do
    {:ok, _} = HakoTest.Minio.start_link()
    Process.sleep(1000)
    HakoTest.Minio.initialize_bucket("default")
    true
  rescue
    RuntimeError -> false
  end

unless minio_available? do
  IO.puts("\n⚠️  Minio not available - S3 tests will be skipped")
  ExUnit.configure(exclude: [:s3])
end

ExUnit.start(capture_log: true)
