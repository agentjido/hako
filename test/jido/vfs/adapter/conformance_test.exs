defmodule Jido.VFS.Adapter.ConformanceTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  alias Jido.VFS.Errors

  test "all adapters reject path traversal and absolute paths", %{tmp_dir: tmp_dir} do
    adapters = [
      Jido.VFS.Adapter.Local.configure(prefix: tmp_dir),
      start_in_memory_adapter(),
      start_ets_adapter(),
      Jido.VFS.Adapter.S3.configure(config: [], bucket: "conformance"),
      Jido.VFS.Adapter.GitHub.configure(owner: "octocat", repo: "hello-world")
    ]

    for filesystem <- adapters do
      assert {:error, %Errors.PathTraversal{}} = Jido.VFS.read(filesystem, "../escape.txt")
      assert {:error, %Errors.AbsolutePath{}} = Jido.VFS.read(filesystem, "/escape.txt")
    end
  end

  @tag :git
  test "git adapter reports unsupported operations with typed errors", %{tmp_dir: tmp_dir} do
    filesystem =
      Jido.VFS.Adapter.Git.configure(
        path: Path.join(tmp_dir, "repo"),
        mode: :manual
      )

    assert Jido.VFS.supports?(filesystem, :stat) == false

    assert {:error, %Errors.UnsupportedOperation{operation: :stat, adapter: Jido.VFS.Adapter.Git}} =
             Jido.VFS.stat(filesystem, "missing.txt")
  end

  test "github adapter reports unsupported operations with typed errors" do
    filesystem = Jido.VFS.Adapter.GitHub.configure(owner: "octocat", repo: "hello-world")

    assert Jido.VFS.supports?(filesystem, :write_stream) == false

    assert {:error,
            %Errors.UnsupportedOperation{
              operation: :write_stream,
              adapter: Jido.VFS.Adapter.GitHub
            }} = Jido.VFS.write_stream(filesystem, "file.txt")
  end

  defp start_in_memory_adapter do
    name = :"conformance_in_memory_#{System.unique_integer([:positive, :monotonic])}"
    filesystem = Jido.VFS.Adapter.InMemory.configure(name: name)
    start_supervised!(filesystem)
    filesystem
  end

  defp start_ets_adapter do
    name = :"conformance_ets_#{System.unique_integer([:positive, :monotonic])}"
    filesystem = Jido.VFS.Adapter.ETS.configure(name: name)
    start_supervised!(filesystem)
    filesystem
  end
end
