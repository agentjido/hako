defmodule Jido.VFS.Adapter.ETSTest do
  use ExUnit.Case, async: true
  import Jido.VFS.AdapterTest
  # doctest Jido.VFS.Adapter.ETS

  setup do
    filesystem = Jido.VFS.Adapter.ETS.configure(name: :ets_test)
    start_supervised!(filesystem)
    {:ok, filesystem: filesystem}
  end

  adapter_test %{filesystem: filesystem} do
    {:ok, filesystem: filesystem}
  end

  describe "write" do
    test "success", %{filesystem: filesystem} do
      {_, config} = filesystem

      :ok = Jido.VFS.Adapter.ETS.write(config, "test.txt", "Hello World", [])

      assert {:ok, "Hello World"} = Jido.VFS.Adapter.ETS.read(config, "test.txt")
    end

    test "folders are automatically created if missing", %{filesystem: filesystem} do
      {_, config} = filesystem

      :ok = Jido.VFS.Adapter.ETS.write(config, "folder/test.txt", "Hello World", [])

      assert {:ok, "Hello World"} = Jido.VFS.Adapter.ETS.read(config, "folder/test.txt")
    end

    test "visibility", %{filesystem: filesystem} do
      {_, config} = filesystem

      :ok = Jido.VFS.Adapter.ETS.write(config, "public.txt", "Hello World", visibility: :public)
      :ok = Jido.VFS.Adapter.ETS.write(config, "private.txt", "Hello World", visibility: :private)

      assert {:ok, :public} = Jido.VFS.Adapter.ETS.visibility(config, "public.txt")
      assert {:ok, :private} = Jido.VFS.Adapter.ETS.visibility(config, "private.txt")
    end
  end

  describe "read" do
    test "success", %{filesystem: filesystem} do
      {_, config} = filesystem

      :ok = Jido.VFS.Adapter.ETS.write(config, "test.txt", "Hello World", [])

      assert {:ok, "Hello World"} = Jido.VFS.Adapter.ETS.read(config, "test.txt")
    end

    test "file not found", %{filesystem: filesystem} do
      {_, config} = filesystem

      assert {:error, %Jido.VFS.Errors.FileNotFound{file_path: "nonexistent.txt"}} =
               Jido.VFS.Adapter.ETS.read(config, "nonexistent.txt")
    end
  end

  describe "delete" do
    test "success", %{filesystem: filesystem} do
      {_, config} = filesystem

      :ok = Jido.VFS.Adapter.ETS.write(config, "test.txt", "Hello World", [])
      assert :ok = Jido.VFS.Adapter.ETS.delete(config, "test.txt")

      assert {:error, %Jido.VFS.Errors.FileNotFound{file_path: "test.txt"}} =
               Jido.VFS.Adapter.ETS.read(config, "test.txt")
    end

    test "successful even if no file to delete", %{filesystem: filesystem} do
      {_, config} = filesystem

      assert :ok = Jido.VFS.Adapter.ETS.delete(config, "nonexistent.txt")
    end
  end

  describe "move" do
    test "success", %{filesystem: filesystem} do
      {_, config} = filesystem

      :ok = Jido.VFS.Adapter.ETS.write(config, "source.txt", "Hello World", [])
      assert :ok = Jido.VFS.Adapter.ETS.move(config, "source.txt", "destination.txt", [])

      assert {:error, %Jido.VFS.Errors.FileNotFound{file_path: "source.txt"}} =
               Jido.VFS.Adapter.ETS.read(config, "source.txt")

      assert {:ok, "Hello World"} = Jido.VFS.Adapter.ETS.read(config, "destination.txt")
    end
  end

  describe "copy" do
    test "success", %{filesystem: filesystem} do
      {_, config} = filesystem

      :ok = Jido.VFS.Adapter.ETS.write(config, "source.txt", "Hello World", [])
      assert :ok = Jido.VFS.Adapter.ETS.copy(config, "source.txt", "destination.txt", [])
      assert {:ok, "Hello World"} = Jido.VFS.Adapter.ETS.read(config, "source.txt")
      assert {:ok, "Hello World"} = Jido.VFS.Adapter.ETS.read(config, "destination.txt")
    end

    test "copy_between_filesystem copies across different ETS instances" do
      source_table = :"ets_copy_src_#{System.unique_integer([:positive])}"
      destination_table = :"ets_copy_dst_#{System.unique_integer([:positive])}"

      source_fs = Jido.VFS.Adapter.ETS.configure(name: source_table)
      destination_fs = Jido.VFS.Adapter.ETS.configure(name: destination_table)

      start_supervised!({Jido.VFS.Adapter.ETS, source_fs}, id: {:source_copy_ets, source_table})

      start_supervised!({Jido.VFS.Adapter.ETS, destination_fs},
        id: {:destination_copy_ets, destination_table}
      )

      assert :ok = Jido.VFS.write(source_fs, "source.txt", "Hello World")

      assert :ok =
               Jido.VFS.copy_between_filesystem(
                 {source_fs, "source.txt"},
                 {destination_fs, "destination.txt"}
               )

      assert {:ok, "Hello World"} = Jido.VFS.read(destination_fs, "destination.txt")
      assert {:ok, :missing} = Jido.VFS.file_exists(source_fs, "destination.txt")
    end
  end

  describe "file_exists" do
    test "existing file", %{filesystem: filesystem} do
      {_, config} = filesystem

      :ok = Jido.VFS.Adapter.ETS.write(config, "test.txt", "Hello World", [])
      assert {:ok, :exists} = Jido.VFS.Adapter.ETS.file_exists(config, "test.txt")
    end

    test "non-existing file", %{filesystem: filesystem} do
      {_, config} = filesystem

      assert {:ok, :missing} = Jido.VFS.Adapter.ETS.file_exists(config, "nonexistent.txt")
    end
  end

  describe "list_contents" do
    test "success", %{filesystem: filesystem} do
      {_, config} = filesystem

      :ok = Jido.VFS.Adapter.ETS.write(config, "file1.txt", "Content 1", [])
      :ok = Jido.VFS.Adapter.ETS.write(config, "file2.txt", "Content 2", [])
      :ok = Jido.VFS.Adapter.ETS.create_directory(config, "dir1", [])

      {:ok, contents} = Jido.VFS.Adapter.ETS.list_contents(config, ".")

      assert Enum.any?(contents, fn item -> item.name == "file1.txt" end)
      assert Enum.any?(contents, fn item -> item.name == "file2.txt" end)
      assert Enum.any?(contents, fn item -> item.name == "dir1" end)
    end
  end

  describe "create_directory" do
    test "success", %{filesystem: filesystem} do
      {_, config} = filesystem

      assert :ok = Jido.VFS.Adapter.ETS.create_directory(config, "new_dir", [])
      assert {:ok, :exists} = Jido.VFS.Adapter.ETS.file_exists(config, "new_dir")
    end
  end

  describe "delete_directory" do
    test "success", %{filesystem: filesystem} do
      {_, config} = filesystem

      :ok = Jido.VFS.Adapter.ETS.create_directory(config, "dir_to_delete", [])
      assert :ok = Jido.VFS.Adapter.ETS.delete_directory(config, "dir_to_delete", [])
      assert {:ok, :missing} = Jido.VFS.Adapter.ETS.file_exists(config, "dir_to_delete")
    end

    test "recursive delete", %{filesystem: filesystem} do
      {_, config} = filesystem

      :ok = Jido.VFS.Adapter.ETS.create_directory(config, "parent_dir", [])
      :ok = Jido.VFS.Adapter.ETS.write(config, "parent_dir/file.txt", "Content", [])

      assert :ok = Jido.VFS.Adapter.ETS.delete_directory(config, "parent_dir", recursive: true)
      assert {:ok, :missing} = Jido.VFS.Adapter.ETS.file_exists(config, "parent_dir")
      assert {:ok, :missing} = Jido.VFS.Adapter.ETS.file_exists(config, "parent_dir/file.txt")
    end

    test "recursive delete does not remove similarly prefixed sibling directories", %{filesystem: filesystem} do
      {_, config} = filesystem

      :ok = Jido.VFS.Adapter.ETS.write(config, "foo/a.txt", "a", [])
      :ok = Jido.VFS.Adapter.ETS.write(config, "foobar/b.txt", "b", [])

      assert :ok = Jido.VFS.Adapter.ETS.delete_directory(config, "foo", recursive: true)
      assert {:ok, :missing} = Jido.VFS.Adapter.ETS.file_exists(config, "foo/a.txt")
      assert {:ok, :exists} = Jido.VFS.Adapter.ETS.file_exists(config, "foobar/b.txt")
    end
  end

  describe "eternal functionality" do
    @tag :eternal
    test "eternal tables survive and persist data across adapter restarts" do
      table_name = :"eternal_test_#{System.unique_integer([:positive])}"

      # Start the eternal table first
      {:ok, _eternal_pid} = Eternal.start_link(table_name, [:set, :public])

      # Configure filesystem to use the eternal table
      eternal_filesystem = Jido.VFS.Adapter.ETS.configure(name: table_name, eternal: true)

      # Start first adapter process and write data
      {:ok, pid1} = Jido.VFS.Adapter.ETS.start_link(eternal_filesystem)
      {_, config} = eternal_filesystem

      :ok = Jido.VFS.Adapter.ETS.write(config, "persistent.txt", "This should survive", [])
      assert {:ok, "This should survive"} = Jido.VFS.Adapter.ETS.read(config, "persistent.txt")

      # Stop the adapter process
      GenServer.stop(pid1, :normal)
      Process.sleep(10)

      # Verify data is still in the eternal table directly
      assert [{"persistent.txt", {"This should survive", %{visibility: :private}}}] =
               :ets.lookup(table_name, "persistent.txt")

      # Start a new adapter process using the same eternal table
      {:ok, _pid2} = Jido.VFS.Adapter.ETS.start_link(eternal_filesystem)

      # Data should still be accessible through the new adapter
      assert {:ok, "This should survive"} = Jido.VFS.Adapter.ETS.read(config, "persistent.txt")

      # Clean up the eternal table
      Eternal.stop(table_name)
    end

    @tag :eternal
    test "eternal tables persist data independently of adapter process" do
      table_name = :"eternal_independent_#{System.unique_integer([:positive])}"

      # Start eternal table directly 
      {:ok, _eternal_pid} = Eternal.start_link(table_name, [:set, :public])

      # Insert data directly into the ETS table
      :ets.insert(table_name, {"direct_key", "direct_value"})

      # Configure filesystem to use the same eternal table
      eternal_filesystem = Jido.VFS.Adapter.ETS.configure(name: table_name, eternal: true)

      # Start and stop the adapter multiple times
      {:ok, pid1} = Jido.VFS.Adapter.ETS.start_link(eternal_filesystem)
      {_, config} = eternal_filesystem

      # Write via adapter
      :ok = Jido.VFS.Adapter.ETS.write(config, "adapter.txt", "adapter data", [])
      assert {:ok, "adapter data"} = Jido.VFS.Adapter.ETS.read(config, "adapter.txt")

      # Data inserted directly should still be there
      assert [{"direct_key", "direct_value"}] = :ets.lookup(table_name, "direct_key")

      # Stop adapter
      GenServer.stop(pid1, :normal)
      Process.sleep(10)

      # Start new adapter process with same table
      {:ok, _pid2} = Jido.VFS.Adapter.ETS.start_link(eternal_filesystem)

      # Both sets of data should still be accessible
      assert {:ok, "adapter data"} = Jido.VFS.Adapter.ETS.read(config, "adapter.txt")
      assert [{"direct_key", "direct_value"}] = :ets.lookup(table_name, "direct_key")

      # Clean up
      Eternal.stop(table_name)
    end

    @tag :eternal
    test "non-eternal tables do not survive process termination" do
      table_name = :"regular_test_#{System.unique_integer([:positive])}"

      # Configure filesystem without eternal (default behavior)
      regular_filesystem = Jido.VFS.Adapter.ETS.configure(name: table_name, eternal: false)

      # Start the filesystem and write data
      {:ok, pid} = Jido.VFS.Adapter.ETS.start_link(regular_filesystem)
      {_, config} = regular_filesystem

      :ok = Jido.VFS.Adapter.ETS.write(config, "temporary.txt", "This will be lost", [])
      assert {:ok, "This will be lost"} = Jido.VFS.Adapter.ETS.read(config, "temporary.txt")

      # Get the actual ETS table reference for verification
      table_ref = config.table

      # Stop the process normally
      GenServer.stop(pid, :normal)
      Process.sleep(10)

      # Verify the table is gone
      assert :undefined = :ets.info(table_ref)

      # Restart the filesystem - should create a new table
      {:ok, _new_pid} = Jido.VFS.Adapter.ETS.start_link(regular_filesystem)

      # Data should be gone (regular ETS table died with process)
      assert {:error, %Jido.VFS.Errors.FileNotFound{file_path: "temporary.txt"}} =
               Jido.VFS.Adapter.ETS.read(config, "temporary.txt")
    end

    test "eternal configuration defaults to false" do
      filesystem = Jido.VFS.Adapter.ETS.configure(name: :default_test)
      {_, config} = filesystem

      # Should default to non-eternal
      assert config.eternal == false
    end

    test "eternal configuration can be explicitly set to true" do
      filesystem = Jido.VFS.Adapter.ETS.configure(name: :explicit_eternal, eternal: true)
      {_, config} = filesystem

      assert config.eternal == true
    end

    test "eternal configuration can be explicitly set to false" do
      filesystem = Jido.VFS.Adapter.ETS.configure(name: :explicit_regular, eternal: false)
      {_, config} = filesystem

      assert config.eternal == false
    end
  end

  describe "versioning" do
    test "write_version creates version and returns version_id", %{filesystem: filesystem} do
      {_, config} = filesystem

      assert {:ok, version_id} =
               Jido.VFS.Adapter.ETS.write_version(config, "test.txt", "Hello World v1", [])

      assert is_binary(version_id)
      assert String.length(version_id) == 32
    end

    test "read_version retrieves specific version", %{filesystem: filesystem} do
      {_, config} = filesystem

      {:ok, version_id} =
        Jido.VFS.Adapter.ETS.write_version(config, "test.txt", "Hello World v1", [])

      assert {:ok, "Hello World v1"} =
               Jido.VFS.Adapter.ETS.read_version(config, "test.txt", version_id)
    end

    test "list_versions returns all versions for a path", %{filesystem: filesystem} do
      {_, config} = filesystem

      {:ok, v1} = Jido.VFS.Adapter.ETS.write_version(config, "test.txt", "Version 1", [])
      {:ok, v2} = Jido.VFS.Adapter.ETS.write_version(config, "test.txt", "Version 2", [])

      {:ok, versions} = Jido.VFS.Adapter.ETS.list_versions(config, "test.txt")
      assert length(versions) == 2
      assert Enum.any?(versions, &(&1.version_id == v1))
      assert Enum.any?(versions, &(&1.version_id == v2))
    end

    test "get_latest_version returns most recent version", %{filesystem: filesystem} do
      {_, config} = filesystem

      {:ok, _v1} = Jido.VFS.Adapter.ETS.write_version(config, "test.txt", "Version 1", [])
      {:ok, v2} = Jido.VFS.Adapter.ETS.write_version(config, "test.txt", "Version 2", [])

      assert {:ok, ^v2} = Jido.VFS.Adapter.ETS.get_latest_version(config, "test.txt")
    end

    test "restore_version restores file to specific version", %{filesystem: filesystem} do
      {_, config} = filesystem

      {:ok, v1} = Jido.VFS.Adapter.ETS.write_version(config, "test.txt", "Version 1", [])
      {:ok, _v2} = Jido.VFS.Adapter.ETS.write_version(config, "test.txt", "Version 2", [])

      assert :ok = Jido.VFS.Adapter.ETS.restore_version(config, "test.txt", v1)
      assert {:ok, "Version 1"} = Jido.VFS.Adapter.ETS.read(config, "test.txt")
    end

    test "delete_version removes specific version", %{filesystem: filesystem} do
      {_, config} = filesystem

      {:ok, v1} = Jido.VFS.Adapter.ETS.write_version(config, "test.txt", "Version 1", [])
      {:ok, v2} = Jido.VFS.Adapter.ETS.write_version(config, "test.txt", "Version 2", [])

      assert :ok = Jido.VFS.Adapter.ETS.delete_version(config, "test.txt", v1)

      {:ok, versions} = Jido.VFS.Adapter.ETS.list_versions(config, "test.txt")
      assert length(versions) == 1
      assert hd(versions).version_id == v2

      assert {:error, _} = Jido.VFS.Adapter.ETS.read_version(config, "test.txt", v1)
    end

    test "versioning preserves visibility", %{filesystem: filesystem} do
      {_, config} = filesystem

      {:ok, version_id} =
        Jido.VFS.Adapter.ETS.write_version(config, "test.txt", "Content", visibility: :public)

      assert :ok = Jido.VFS.Adapter.ETS.restore_version(config, "test.txt", version_id)
      assert {:ok, :public} = Jido.VFS.Adapter.ETS.visibility(config, "test.txt")
    end
  end
end
