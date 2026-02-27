defmodule Jido.VFS.Adapter.MetadataContractTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  @adapters [
    Jido.VFS.Adapter.Local,
    Jido.VFS.Adapter.InMemory,
    Jido.VFS.Adapter.ETS,
    Jido.VFS.Adapter.S3,
    Jido.VFS.Adapter.Git,
    Jido.VFS.Adapter.GitHub,
    Jido.VFS.Adapter.Sprite
  ]

  test "all built-in adapters expose required metadata callbacks" do
    Enum.each(@adapters, fn adapter ->
      assert Code.ensure_loaded?(adapter), "adapter module failed to load: #{inspect(adapter)}"

      assert function_exported?(adapter, :unsupported_operations, 0),
             "#{inspect(adapter)} must implement unsupported_operations/0"

      assert function_exported?(adapter, :versioning_module, 0),
             "#{inspect(adapter)} must implement versioning_module/0"
    end)
  end

  test "unsupported_operations callback returns a list of atoms" do
    Enum.each(@adapters, fn adapter ->
      operations = adapter.unsupported_operations()

      assert is_list(operations),
             "#{inspect(adapter)}.unsupported_operations/0 must return a list"

      assert Enum.all?(operations, &is_atom/1),
             "#{inspect(adapter)}.unsupported_operations/0 must contain only atoms"
    end)
  end

  test "versioning_module callback returns nil or a loaded module" do
    Enum.each(@adapters, fn adapter ->
      versioning_module = adapter.versioning_module()

      assert is_nil(versioning_module) or is_atom(versioning_module),
             "#{inspect(adapter)}.versioning_module/0 must return a module or nil"

      if is_atom(versioning_module) and not is_nil(versioning_module) do
        assert Code.ensure_loaded?(versioning_module),
               "#{inspect(adapter)}.versioning_module/0 returned an unloaded module: #{inspect(versioning_module)}"
      end
    end)
  end

  test "missing metadata callbacks are caught by behaviour warnings" do
    module_name =
      Module.concat([
        __MODULE__,
        :"MissingMetadata#{System.unique_integer([:positive, :monotonic])}"
      ])

    module_source = """
    defmodule #{inspect(module_name)} do
      @behaviour Jido.VFS.Adapter

      def starts_processes, do: false
      def configure(_opts), do: {__MODULE__, %{}}
      def write(_config, _path, _contents, _opts), do: :ok
      def write_stream(_config, _path, _opts), do: {:ok, []}
      def read(_config, _path), do: {:ok, ""}
      def read_stream(_config, _path, _opts), do: {:ok, []}
      def delete(_config, _path), do: :ok
      def move(_config, _source, _destination, _opts), do: :ok
      def copy(_config, _source, _destination, _opts), do: :ok
      def copy(_source_config, _source, _destination_config, _destination, _opts), do: :ok
      def file_exists(_config, _path), do: {:ok, :missing}
      def list_contents(_config, _path), do: {:ok, []}
      def create_directory(_config, _path, _opts), do: :ok
      def delete_directory(_config, _path, _opts), do: :ok
      def clear(_config), do: :ok
      def set_visibility(_config, _path, _visibility), do: :ok
      def visibility(_config, _path), do: {:ok, :private}
    end
    """

    warnings =
      capture_io(:stderr, fn ->
        Code.compile_string(module_source)
      end)

    assert warnings =~ "unsupported_operations/0"
    assert warnings =~ "versioning_module/0"
  end
end
