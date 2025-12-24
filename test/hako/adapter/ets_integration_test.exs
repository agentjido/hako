defmodule Hako.Adapter.ETSIntegrationTest do
  @moduledoc """
  Comprehensive integration tests for the ETS adapter.

  These tests exercise edge cases, error conditions, and boundary scenarios
  to ensure the adapter returns proper error types and handles all cases gracefully.

  The ETS adapter uses GenServer + ETS tables with these key features:
  - GenServer managing ETS tables with Hako.Registry
  - Optional Eternal library support for persistent tables
  - ETSStream for streaming (implements Collectable protocol)
  - Versioning support with separate versions_table
  - Path normalization (strips trailing slashes)
  - Parent directory auto-creation

  Run with: mix test --include integration
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  setup do
    table_name = :"ets_integration_#{System.unique_integer([:positive])}"
    filesystem = Hako.Adapter.ETS.configure(name: table_name)
    start_supervised!(filesystem)
    {_, config} = filesystem
    {:ok, filesystem: filesystem, config: config, table_name: table_name}
  end

  # ============================================================================
  # CORE OPERATIONS: Write/Read/Delete/Move/Copy
  # ============================================================================

  describe "core operations - happy paths" do
    test "basic write/read roundtrip", %{filesystem: fs} do
      assert :ok = Hako.write(fs, "file.txt", "hello")
      assert {:ok, "hello"} = Hako.read(fs, "file.txt")
    end

    test "write with iodata (list)", %{filesystem: fs} do
      assert :ok = Hako.write(fs, "iodata.txt", ["he", "llo", " ", "world"])
      assert {:ok, "hello world"} = Hako.read(fs, "iodata.txt")
    end

    test "write with binary iodata", %{filesystem: fs} do
      assert :ok = Hako.write(fs, "binary.txt", ["he", <<"llo">>])
      assert {:ok, "hello"} = Hako.read(fs, "binary.txt")
    end

    test "empty file", %{filesystem: fs} do
      assert :ok = Hako.write(fs, "empty.bin", "")
      assert {:ok, ""} = Hako.read(fs, "empty.bin")
    end

    test "binary data with null bytes", %{filesystem: fs} do
      content = <<0, 1, 255, 0, 42, 128, 200>>
      assert :ok = Hako.write(fs, "binary.bin", content)
      assert {:ok, ^content} = Hako.read(fs, "binary.bin")
    end

    test "moderately large file (1MB)", %{filesystem: fs} do
      content = :crypto.strong_rand_bytes(1_024 * 1_024)
      assert :ok = Hako.write(fs, "large.bin", content)
      assert {:ok, read_content} = Hako.read(fs, "large.bin")
      assert byte_size(read_content) == byte_size(content)
      assert content == read_content
    end

    test "overwrite existing file", %{filesystem: fs} do
      assert :ok = Hako.write(fs, "overwrite.txt", "original")
      assert :ok = Hako.write(fs, "overwrite.txt", "updated")
      assert {:ok, "updated"} = Hako.read(fs, "overwrite.txt")
    end

    test "move file", %{filesystem: fs} do
      assert :ok = Hako.write(fs, "src.txt", "content")
      assert :ok = Hako.move(fs, "src.txt", "moved.txt")
      assert {:error, %Hako.Errors.FileNotFound{}} = Hako.read(fs, "src.txt")
      assert {:ok, "content"} = Hako.read(fs, "moved.txt")
    end

    test "copy file", %{filesystem: fs} do
      assert :ok = Hako.write(fs, "original.txt", "content")
      assert :ok = Hako.copy(fs, "original.txt", "copy.txt")
      assert {:ok, "content"} = Hako.read(fs, "original.txt")
      assert {:ok, "content"} = Hako.read(fs, "copy.txt")
    end

    test "delete file", %{filesystem: fs} do
      assert :ok = Hako.write(fs, "delete_me.txt", "content")
      assert :ok = Hako.delete(fs, "delete_me.txt")
      assert {:error, %Hako.Errors.FileNotFound{}} = Hako.read(fs, "delete_me.txt")
    end

    test "delete non-existing file is idempotent", %{filesystem: fs} do
      assert :ok = Hako.delete(fs, "does_not_exist.txt")
    end
  end

  # ============================================================================
  # PATH EDGE CASES
  # ============================================================================

  describe "path edge cases" do
    test "unicode filenames", %{filesystem: fs} do
      assert :ok = Hako.write(fs, "ümlaut.txt", "german")
      assert {:ok, "german"} = Hako.read(fs, "ümlaut.txt")

      assert :ok = Hako.write(fs, "日本語.txt", "japanese")
      assert {:ok, "japanese"} = Hako.read(fs, "日本語.txt")

      assert :ok = Hako.write(fs, "emoji_🎉.txt", "party")
      assert {:ok, "party"} = Hako.read(fs, "emoji_🎉.txt")
    end

    test "unicode nested paths", %{filesystem: fs} do
      assert :ok = Hako.write(fs, "日本語/ファイル.txt", "nested")
      assert {:ok, "nested"} = Hako.read(fs, "日本語/ファイル.txt")
    end

    test "unicode content", %{filesystem: fs} do
      content = "こんにちは世界 🌍 مرحبا"
      assert :ok = Hako.write(fs, "unicode_content.txt", content)
      assert {:ok, ^content} = Hako.read(fs, "unicode_content.txt")
    end

    test "special characters in filenames", %{filesystem: fs} do
      assert :ok = Hako.write(fs, "file with spaces.txt", "spaces")
      assert {:ok, "spaces"} = Hako.read(fs, "file with spaces.txt")

      assert :ok = Hako.write(fs, "file-with-dashes.txt", "dashes")
      assert {:ok, "dashes"} = Hako.read(fs, "file-with-dashes.txt")

      assert :ok = Hako.write(fs, "file_with_underscores.txt", "underscores")
      assert {:ok, "underscores"} = Hako.read(fs, "file_with_underscores.txt")
    end

    test "deeply nested path", %{filesystem: fs} do
      deep_path = Enum.map_join(1..20, "/", fn n -> "dir#{n}" end) <> "/file.txt"
      assert :ok = Hako.write(fs, deep_path, "deep content")
      assert {:ok, "deep content"} = Hako.read(fs, deep_path)
    end

    test "path normalization - trailing slashes stripped for files", %{filesystem: fs} do
      assert :ok = Hako.write(fs, "file.txt", "content")
      assert {:ok, :exists} = Hako.file_exists(fs, "file.txt")
      assert {:ok, :exists} = Hako.file_exists(fs, "file.txt/")
    end

    test "path normalization for directories", %{filesystem: fs} do
      assert :ok = Hako.create_directory(fs, "testdir/")
      assert {:ok, :exists} = Hako.file_exists(fs, "testdir")
      assert {:ok, :exists} = Hako.file_exists(fs, "testdir/")
    end

    test "path with multiple consecutive slashes", %{filesystem: fs} do
      assert :ok = Hako.write(fs, "a//b///c/file.txt", "content")
      assert {:ok, "content"} = Hako.read(fs, "a//b///c/file.txt")
    end

    test "parent directories are auto-created on write", %{filesystem: fs} do
      assert :ok = Hako.write(fs, "auto/created/dir/file.txt", "content")
      assert {:ok, :exists} = Hako.file_exists(fs, "auto")
      assert {:ok, :exists} = Hako.file_exists(fs, "auto/created")
      assert {:ok, :exists} = Hako.file_exists(fs, "auto/created/dir")
    end

    test "hidden files (dot prefix)", %{filesystem: fs} do
      assert :ok = Hako.write(fs, ".hidden", "secret")
      assert {:ok, "secret"} = Hako.read(fs, ".hidden")
      assert {:ok, :exists} = Hako.file_exists(fs, ".hidden")
    end

    test "files with multiple dots", %{filesystem: fs} do
      assert :ok = Hako.write(fs, "file.test.backup.txt", "content")
      assert {:ok, "content"} = Hako.read(fs, "file.test.backup.txt")
    end
  end

  # ============================================================================
  # ERROR CONDITIONS
  # ============================================================================

  describe "error conditions - file not found" do
    test "read missing file", %{filesystem: fs} do
      assert {:error, %Hako.Errors.FileNotFound{file_path: path}} =
               Hako.read(fs, "missing.txt")

      assert path =~ "missing.txt"
    end

    test "read from nested missing path", %{filesystem: fs} do
      assert {:error, %Hako.Errors.FileNotFound{}} =
               Hako.read(fs, "no_such_dir/missing.txt")
    end

    test "move missing file", %{filesystem: fs} do
      assert {:error, %Hako.Errors.FileNotFound{}} = Hako.move(fs, "missing.txt", "dest.txt")
    end

    test "copy missing file", %{filesystem: fs} do
      assert {:error, %Hako.Errors.FileNotFound{}} = Hako.copy(fs, "missing.txt", "dest.txt")
    end

    test "visibility of missing file", %{filesystem: fs} do
      assert {:error, %Hako.Errors.FileNotFound{}} = Hako.visibility(fs, "missing.txt")
    end

    test "set visibility on missing file", %{filesystem: fs} do
      assert {:error, %Hako.Errors.FileNotFound{}} =
               Hako.set_visibility(fs, "nonexistent.txt", :public)
    end
  end

  describe "error conditions - directory errors" do
    test "delete non-empty directory without recursive fails", %{filesystem: fs} do
      :ok = Hako.write(fs, "non_empty/file.txt", "content")

      assert {:error, %Hako.Errors.DirectoryNotEmpty{}} =
               Hako.delete_directory(fs, "non_empty/", recursive: false)
    end

    test "delete non-existent directory", %{filesystem: fs} do
      assert {:error, %Hako.Errors.DirectoryNotFound{}} =
               Hako.delete_directory(fs, "nonexistent/", recursive: false)
    end

    test "delete file as directory fails", %{filesystem: fs} do
      :ok = Hako.write(fs, "file.txt", "content")

      assert {:error, %Hako.Errors.DirectoryNotFound{}} =
               Hako.delete_directory(fs, "file.txt/")
    end
  end

  # ============================================================================
  # DIRECTORY OPERATIONS
  # ============================================================================

  describe "directory operations" do
    test "create directory", %{filesystem: fs} do
      assert :ok = Hako.create_directory(fs, "new_dir/")
      assert {:ok, :exists} = Hako.file_exists(fs, "new_dir/")
    end

    test "create nested directories", %{filesystem: fs} do
      assert :ok = Hako.create_directory(fs, "a/b/c/d/e/")
      assert {:ok, :exists} = Hako.file_exists(fs, "a")
      assert {:ok, :exists} = Hako.file_exists(fs, "a/b")
      assert {:ok, :exists} = Hako.file_exists(fs, "a/b/c")
      assert {:ok, :exists} = Hako.file_exists(fs, "a/b/c/d")
      assert {:ok, :exists} = Hako.file_exists(fs, "a/b/c/d/e")
    end

    test "delete empty directory", %{filesystem: fs} do
      :ok = Hako.create_directory(fs, "empty_dir/")
      assert :ok = Hako.delete_directory(fs, "empty_dir/")
      assert {:ok, :missing} = Hako.file_exists(fs, "empty_dir/")
    end

    test "delete non-empty directory with recursive", %{filesystem: fs} do
      :ok = Hako.write(fs, "to_delete/a/b/file.txt", "content")
      :ok = Hako.write(fs, "to_delete/file2.txt", "content2")
      assert :ok = Hako.delete_directory(fs, "to_delete/", recursive: true)
      assert {:ok, :missing} = Hako.file_exists(fs, "to_delete/")
      assert {:ok, :missing} = Hako.file_exists(fs, "to_delete/a/")
      assert {:ok, :missing} = Hako.file_exists(fs, "to_delete/file2.txt")
    end

    test "list contents returns files and directories", %{filesystem: fs} do
      :ok = Hako.write(fs, "file1.txt", "content")
      :ok = Hako.write(fs, "file2.txt", "content")
      :ok = Hako.create_directory(fs, "subdir/")

      assert {:ok, contents} = Hako.list_contents(fs, ".")
      assert length(contents) == 3

      assert Enum.any?(contents, &match?(%Hako.Stat.File{name: "file1.txt"}, &1))
      assert Enum.any?(contents, &match?(%Hako.Stat.File{name: "file2.txt"}, &1))
      assert Enum.any?(contents, &match?(%Hako.Stat.Dir{name: "subdir"}, &1))
    end

    test "list contents of nested directory", %{filesystem: fs} do
      :ok = Hako.write(fs, "parent/child1.txt", "content1")
      :ok = Hako.write(fs, "parent/child2.txt", "content2")
      :ok = Hako.create_directory(fs, "parent/nested/")

      {:ok, contents} = Hako.list_contents(fs, "parent")
      assert length(contents) == 3

      assert Enum.any?(contents, &match?(%Hako.Stat.File{name: "child1.txt"}, &1))
      assert Enum.any?(contents, &match?(%Hako.Stat.File{name: "child2.txt"}, &1))
      assert Enum.any?(contents, &match?(%Hako.Stat.Dir{name: "nested"}, &1))
    end

    test "list contents of empty directory", %{filesystem: fs} do
      :ok = Hako.create_directory(fs, "empty/")
      assert {:ok, []} = Hako.list_contents(fs, "empty")
    end

    test "clear filesystem", %{filesystem: fs} do
      :ok = Hako.write(fs, "file1.txt", "content")
      :ok = Hako.write(fs, "dir/file2.txt", "content")
      :ok = Hako.create_directory(fs, "empty_dir/")

      assert :ok = Hako.clear(fs)

      assert {:ok, :missing} = Hako.file_exists(fs, "file1.txt")
      assert {:ok, :missing} = Hako.file_exists(fs, "dir/file2.txt")
      assert {:ok, :missing} = Hako.file_exists(fs, "empty_dir/")
    end

    test "hidden files are included in listing", %{filesystem: fs} do
      :ok = Hako.write(fs, ".hidden", "secret")
      :ok = Hako.write(fs, "visible.txt", "public")

      assert {:ok, contents} = Hako.list_contents(fs, ".")
      assert Enum.any?(contents, &match?(%Hako.Stat.File{name: ".hidden"}, &1))
    end
  end

  # ============================================================================
  # STREAM OPERATIONS
  # ============================================================================

  describe "stream operations" do
    test "write stream via Collectable", %{filesystem: fs} do
      assert {:ok, stream} = Hako.write_stream(fs, "stream_write.txt")
      Enum.into(["Hello", " ", "World"], stream)
      assert {:ok, "Hello World"} = Hako.read(fs, "stream_write.txt")
    end

    test "write stream with binary chunks", %{filesystem: fs} do
      {:ok, stream} = Hako.write_stream(fs, "binary_stream.bin")
      chunks = [<<1, 2, 3>>, <<4, 5, 6>>, <<7, 8, 9>>]
      Enum.into(chunks, stream)
      assert {:ok, <<1, 2, 3, 4, 5, 6, 7, 8, 9>>} = Hako.read(fs, "binary_stream.bin")
    end

    test "write stream appends to existing content", %{filesystem: fs} do
      {:ok, stream1} = Hako.write_stream(fs, "append_stream.txt")
      Enum.into(["First"], stream1)

      {:ok, stream2} = Hako.write_stream(fs, "append_stream.txt")
      Enum.into([" Second"], stream2)

      assert {:ok, "First Second"} = Hako.read(fs, "append_stream.txt")
    end

    test "read stream with default chunk size", %{filesystem: fs} do
      content = String.duplicate("a", 2048)
      :ok = Hako.write(fs, "stream_read.txt", content)
      assert {:ok, stream} = Hako.read_stream(fs, "stream_read.txt")
      assert Enum.into(stream, <<>>) == content
    end

    test "read stream with custom chunk size", %{filesystem: fs} do
      :ok = Hako.write(fs, "chunked.txt", "abcdef")
      assert {:ok, stream} = Hako.read_stream(fs, "chunked.txt", chunk_size: 2)
      chunks = Enum.to_list(stream)
      assert chunks == ["ab", "cd", "ef"]
    end

    test "read stream with chunk size larger than content", %{filesystem: fs} do
      :ok = Hako.write(fs, "small.txt", "abc")
      {:ok, stream} = Hako.read_stream(fs, "small.txt", chunk_size: 1000)
      assert Enum.to_list(stream) == ["abc"]
    end

    test "read stream of empty file", %{filesystem: fs} do
      :ok = Hako.write(fs, "empty.txt", "")
      {:ok, stream} = Hako.read_stream(fs, "empty.txt")
      assert Enum.to_list(stream) == []
    end

    test "read stream of missing file returns error", %{filesystem: fs} do
      assert {:error, %Hako.Errors.FileNotFound{}} =
               Hako.read_stream(fs, "missing.txt")
    end

    test "partial stream consumption", %{filesystem: fs} do
      :ok = Hako.write(fs, "partial.txt", "abcdefghij")
      {:ok, stream} = Hako.read_stream(fs, "partial.txt", chunk_size: 2)

      first_two = stream |> Stream.take(2) |> Enum.to_list()
      assert first_two == ["ab", "cd"]
    end

    test "stream with large binary data", %{filesystem: fs} do
      content = :crypto.strong_rand_bytes(100_000)
      :ok = Hako.write(fs, "large_stream.bin", content)
      {:ok, stream} = Hako.read_stream(fs, "large_stream.bin", chunk_size: 10_000)

      chunks = Enum.to_list(stream)
      assert length(chunks) == 10
      assert Enum.into(chunks, <<>>) == content
    end
  end

  # ============================================================================
  # VISIBILITY OPERATIONS
  # ============================================================================

  describe "visibility operations" do
    test "write with public visibility", %{filesystem: fs} do
      :ok = Hako.write(fs, "public.txt", "content", visibility: :public)
      assert {:ok, :public} = Hako.visibility(fs, "public.txt")
    end

    test "write with private visibility", %{filesystem: fs} do
      :ok = Hako.write(fs, "private.txt", "content", visibility: :private)
      assert {:ok, :private} = Hako.visibility(fs, "private.txt")
    end

    test "default visibility is private", %{filesystem: fs} do
      :ok = Hako.write(fs, "default_vis.txt", "content")
      assert {:ok, :private} = Hako.visibility(fs, "default_vis.txt")
    end

    test "set visibility on existing file", %{filesystem: fs} do
      :ok = Hako.write(fs, "change_vis.txt", "content", visibility: :public)
      assert {:ok, :public} = Hako.visibility(fs, "change_vis.txt")

      :ok = Hako.set_visibility(fs, "change_vis.txt", :private)
      assert {:ok, :private} = Hako.visibility(fs, "change_vis.txt")
    end

    test "visibility toggle back and forth", %{filesystem: fs} do
      :ok = Hako.write(fs, "toggle.txt", "content", visibility: :public)
      :ok = Hako.set_visibility(fs, "toggle.txt", :private)
      :ok = Hako.set_visibility(fs, "toggle.txt", :public)
      :ok = Hako.set_visibility(fs, "toggle.txt", :private)
      assert {:ok, :private} = Hako.visibility(fs, "toggle.txt")
    end

    test "directory visibility on auto-created dirs", %{filesystem: fs} do
      :ok = Hako.write(fs, "public_dir/file.txt", "content", directory_visibility: :public)
      :ok = Hako.write(fs, "private_dir/file.txt", "content", directory_visibility: :private)

      assert {:ok, :public} = Hako.visibility(fs, "public_dir")
      assert {:ok, :private} = Hako.visibility(fs, "private_dir")
    end

    test "set visibility on directory", %{filesystem: fs} do
      :ok = Hako.create_directory(fs, "vis_dir/", directory_visibility: :public)
      assert {:ok, :public} = Hako.visibility(fs, "vis_dir/")

      :ok = Hako.set_visibility(fs, "vis_dir/", :private)
      assert {:ok, :private} = Hako.visibility(fs, "vis_dir/")
    end

    test "visibility propagates to children when set on directory", %{filesystem: fs} do
      :ok = Hako.write(fs, "parent/child1.txt", "content", visibility: :public)
      :ok = Hako.write(fs, "parent/child2.txt", "content", visibility: :public)

      :ok = Hako.set_visibility(fs, "parent", :private)

      assert {:ok, :private} = Hako.visibility(fs, "parent/child1.txt")
      assert {:ok, :private} = Hako.visibility(fs, "parent/child2.txt")
    end

    test "list contents includes visibility info", %{filesystem: fs} do
      :ok = Hako.write(fs, "list_pub.txt", "content", visibility: :public)
      :ok = Hako.write(fs, "list_priv.txt", "content", visibility: :private)

      {:ok, contents} = Hako.list_contents(fs, ".")

      pub_file = Enum.find(contents, &(&1.name == "list_pub.txt"))
      priv_file = Enum.find(contents, &(&1.name == "list_priv.txt"))

      assert pub_file.visibility == :public
      assert priv_file.visibility == :private
    end

    test "root directory has public visibility", %{filesystem: fs} do
      assert {:ok, :public} = Hako.visibility(fs, ".")
    end
  end

  # ============================================================================
  # VERSIONING OPERATIONS
  # ============================================================================

  describe "versioning operations" do
    test "write_version creates version and returns version_id", %{filesystem: fs} do
      {_, config} = fs

      assert {:ok, version_id} =
               Hako.Adapter.ETS.write_version(config, "test.txt", "Hello World v1", [])

      assert is_binary(version_id)
      assert String.length(version_id) == 32
    end

    test "read_version retrieves specific version", %{filesystem: fs} do
      {_, config} = fs

      {:ok, version_id} =
        Hako.Adapter.ETS.write_version(config, "test.txt", "Hello World v1", [])

      assert {:ok, "Hello World v1"} =
               Hako.Adapter.ETS.read_version(config, "test.txt", version_id)
    end

    test "multiple versions of same file", %{filesystem: fs} do
      {_, config} = fs

      {:ok, v1} = Hako.Adapter.ETS.write_version(config, "test.txt", "Version 1", [])
      {:ok, v2} = Hako.Adapter.ETS.write_version(config, "test.txt", "Version 2", [])
      {:ok, v3} = Hako.Adapter.ETS.write_version(config, "test.txt", "Version 3", [])

      assert {:ok, "Version 1"} = Hako.Adapter.ETS.read_version(config, "test.txt", v1)
      assert {:ok, "Version 2"} = Hako.Adapter.ETS.read_version(config, "test.txt", v2)
      assert {:ok, "Version 3"} = Hako.Adapter.ETS.read_version(config, "test.txt", v3)
    end

    test "list_versions returns all versions for a path", %{filesystem: fs} do
      {_, config} = fs

      {:ok, v1} = Hako.Adapter.ETS.write_version(config, "test.txt", "Version 1", [])
      {:ok, v2} = Hako.Adapter.ETS.write_version(config, "test.txt", "Version 2", [])

      {:ok, versions} = Hako.Adapter.ETS.list_versions(config, "test.txt")
      assert length(versions) == 2
      assert Enum.any?(versions, &(&1.version_id == v1))
      assert Enum.any?(versions, &(&1.version_id == v2))
    end

    test "list_versions returns empty list for unversioned file", %{filesystem: fs} do
      {_, config} = fs
      assert {:ok, []} = Hako.Adapter.ETS.list_versions(config, "nonexistent.txt")
    end

    test "versions have timestamps", %{filesystem: fs} do
      {_, config} = fs

      {:ok, _v1} = Hako.Adapter.ETS.write_version(config, "test.txt", "Version 1", [])
      {:ok, versions} = Hako.Adapter.ETS.list_versions(config, "test.txt")

      assert length(versions) == 1
      assert is_integer(hd(versions).timestamp)
      assert hd(versions).timestamp > 0
    end

    test "get_latest_version returns most recent version", %{filesystem: fs} do
      {_, config} = fs

      {:ok, _v1} = Hako.Adapter.ETS.write_version(config, "test.txt", "Version 1", [])
      {:ok, v2} = Hako.Adapter.ETS.write_version(config, "test.txt", "Version 2", [])

      assert {:ok, ^v2} = Hako.Adapter.ETS.get_latest_version(config, "test.txt")
    end

    test "get_latest_version returns error for unversioned file", %{filesystem: fs} do
      {_, config} = fs

      assert {:error, %Hako.Errors.FileNotFound{}} =
               Hako.Adapter.ETS.get_latest_version(config, "nonexistent.txt")
    end

    test "restore_version restores file to specific version", %{filesystem: fs} do
      {_, config} = fs

      {:ok, v1} = Hako.Adapter.ETS.write_version(config, "test.txt", "Version 1", [])
      {:ok, _v2} = Hako.Adapter.ETS.write_version(config, "test.txt", "Version 2", [])

      assert {:ok, "Version 2"} = Hako.Adapter.ETS.read(config, "test.txt")

      assert :ok = Hako.Adapter.ETS.restore_version(config, "test.txt", v1)
      assert {:ok, "Version 1"} = Hako.Adapter.ETS.read(config, "test.txt")
    end

    test "restore_version with nonexistent version returns error", %{filesystem: fs} do
      {_, config} = fs

      {:ok, _v1} = Hako.Adapter.ETS.write_version(config, "test.txt", "Version 1", [])

      assert {:error, %Hako.Errors.FileNotFound{}} =
               Hako.Adapter.ETS.restore_version(config, "test.txt", "nonexistent_version_id")
    end

    test "delete_version removes specific version", %{filesystem: fs} do
      {_, config} = fs

      {:ok, v1} = Hako.Adapter.ETS.write_version(config, "test.txt", "Version 1", [])
      {:ok, v2} = Hako.Adapter.ETS.write_version(config, "test.txt", "Version 2", [])

      assert :ok = Hako.Adapter.ETS.delete_version(config, "test.txt", v1)

      {:ok, versions} = Hako.Adapter.ETS.list_versions(config, "test.txt")
      assert length(versions) == 1
      assert hd(versions).version_id == v2

      assert {:error, _} = Hako.Adapter.ETS.read_version(config, "test.txt", v1)
    end

    test "versioning preserves visibility", %{filesystem: fs} do
      {_, config} = fs

      {:ok, version_id} =
        Hako.Adapter.ETS.write_version(config, "test.txt", "Content", visibility: :public)

      assert :ok = Hako.Adapter.ETS.restore_version(config, "test.txt", version_id)
      assert {:ok, :public} = Hako.Adapter.ETS.visibility(config, "test.txt")
    end

    test "versioning with binary content", %{filesystem: fs} do
      {_, config} = fs
      binary_content = <<0, 1, 2, 255, 254, 253>>

      {:ok, version_id} =
        Hako.Adapter.ETS.write_version(config, "binary.bin", binary_content, [])

      assert {:ok, ^binary_content} =
               Hako.Adapter.ETS.read_version(config, "binary.bin", version_id)
    end

    test "versioning with large content", %{filesystem: fs} do
      {_, config} = fs
      large_content = :crypto.strong_rand_bytes(100_000)

      {:ok, version_id} =
        Hako.Adapter.ETS.write_version(config, "large.bin", large_content, [])

      assert {:ok, ^large_content} =
               Hako.Adapter.ETS.read_version(config, "large.bin", version_id)
    end
  end

  # ============================================================================
  # CONCURRENCY TESTS
  # ============================================================================

  describe "concurrency" do
    test "concurrent reads from multiple processes", %{filesystem: fs} do
      content = :crypto.strong_rand_bytes(10_000)
      :ok = Hako.write(fs, "concurrent_read.txt", content)

      tasks =
        Enum.map(1..20, fn _ ->
          Task.async(fn ->
            Hako.read(fs, "concurrent_read.txt")
          end)
        end)

      results = Task.await_many(tasks)

      assert Enum.all?(results, fn result ->
               result == {:ok, content}
             end)
    end

    test "concurrent writes from multiple processes", %{filesystem: fs} do
      contents = Enum.map(1..10, fn n -> "content_#{n}" end)

      tasks =
        Enum.map(contents, fn content ->
          Task.async(fn ->
            Hako.write(fs, "concurrent.txt", content)
          end)
        end)

      results = Task.await_many(tasks)
      assert Enum.all?(results, &(&1 == :ok))

      {:ok, final_content} = Hako.read(fs, "concurrent.txt")
      assert final_content in contents
    end

    test "concurrent writes to different files", %{filesystem: fs} do
      tasks =
        Enum.map(1..20, fn n ->
          Task.async(fn ->
            path = "concurrent_#{n}.txt"
            content = "content_#{n}"
            :ok = Hako.write(fs, path, content)
            {path, content}
          end)
        end)

      results = Task.await_many(tasks)

      for {path, expected_content} <- results do
        assert {:ok, ^expected_content} = Hako.read(fs, path)
      end
    end

    test "concurrent directory creation", %{filesystem: fs} do
      tasks =
        Enum.map(1..10, fn n ->
          Task.async(fn ->
            result = Hako.write(fs, "concurrent_dir#{n}/file.txt", "content#{n}")
            {n, result}
          end)
        end)

      results = Task.await_many(tasks)

      for {_n, result} <- results do
        assert result == :ok
      end
    end

    test "concurrent versioning operations", %{filesystem: fs} do
      {_, config} = fs

      tasks =
        Enum.map(1..10, fn n ->
          Task.async(fn ->
            Hako.Adapter.ETS.write_version(config, "versioned.txt", "Version #{n}", [])
          end)
        end)

      results = Task.await_many(tasks)

      assert Enum.all?(results, fn
               {:ok, version_id} when is_binary(version_id) -> true
               _ -> false
             end)

      {:ok, versions} = Hako.Adapter.ETS.list_versions(config, "versioned.txt")
      assert length(versions) == 10
    end

    test "genserver serializes operations correctly", %{filesystem: fs} do
      :ok = Hako.write(fs, "serialize.txt", "initial")

      writer =
        Task.async(fn ->
          Process.sleep(10)
          Hako.write(fs, "serialize.txt", "updated")
        end)

      reader =
        Task.async(fn ->
          Process.sleep(20)
          Hako.read(fs, "serialize.txt")
        end)

      assert :ok = Task.await(writer)
      assert {:ok, content} = Task.await(reader)
      assert content in ["initial", "updated"]
    end
  end

  # ============================================================================
  # GENSERVER LIFECYCLE TESTS
  # ============================================================================

  describe "genserver lifecycle" do
    test "state is cleared after clear operation", %{filesystem: fs} do
      :ok = Hako.write(fs, "file1.txt", "content1")
      :ok = Hako.write(fs, "file2.txt", "content2")
      :ok = Hako.create_directory(fs, "dir/")

      :ok = Hako.clear(fs)

      assert {:ok, []} = Hako.list_contents(fs, ".")
    end

    test "can write after clear", %{filesystem: fs} do
      :ok = Hako.write(fs, "before.txt", "before")
      :ok = Hako.clear(fs)
      :ok = Hako.write(fs, "after.txt", "after")

      assert {:ok, :missing} = Hako.file_exists(fs, "before.txt")
      assert {:ok, "after"} = Hako.read(fs, "after.txt")
    end

    test "process restart clears state for non-eternal tables" do
      table_name = :"restart_test_#{System.unique_integer([:positive])}"
      filesystem = Hako.Adapter.ETS.configure(name: table_name, eternal: false)
      {:ok, pid} = Hako.Adapter.ETS.start_link(filesystem)
      {_, config} = filesystem

      :ok = Hako.Adapter.ETS.write(config, "temporary.txt", "This will be lost", [])
      assert {:ok, "This will be lost"} = Hako.Adapter.ETS.read(config, "temporary.txt")

      GenServer.stop(pid, :normal)
      Process.sleep(10)

      {:ok, _new_pid} = Hako.Adapter.ETS.start_link(filesystem)

      assert {:error, %Hako.Errors.FileNotFound{}} =
               Hako.Adapter.ETS.read(config, "temporary.txt")
    end
  end

  # ============================================================================
  # ETERNAL TABLE TESTS
  # ============================================================================

  describe "eternal tables" do
    @describetag :eternal

    test "eternal tables survive process termination" do
      table_name = :"eternal_survival_#{System.unique_integer([:positive])}"

      {:ok, _eternal_pid} = Eternal.start_link(table_name, [:set, :public])

      eternal_filesystem = Hako.Adapter.ETS.configure(name: table_name, eternal: true)
      {:ok, pid1} = Hako.Adapter.ETS.start_link(eternal_filesystem)
      {_, config} = eternal_filesystem

      :ok = Hako.Adapter.ETS.write(config, "persistent.txt", "This should survive", [])
      assert {:ok, "This should survive"} = Hako.Adapter.ETS.read(config, "persistent.txt")

      GenServer.stop(pid1, :normal)
      Process.sleep(10)

      assert [{"persistent.txt", {"This should survive", %{visibility: :private}}}] =
               :ets.lookup(table_name, "persistent.txt")

      {:ok, _pid2} = Hako.Adapter.ETS.start_link(eternal_filesystem)
      assert {:ok, "This should survive"} = Hako.Adapter.ETS.read(config, "persistent.txt")

      Eternal.stop(table_name)
    end

    test "data persists across multiple restarts with eternal tables" do
      table_name = :"eternal_multiple_restarts_#{System.unique_integer([:positive])}"

      {:ok, _eternal_pid} = Eternal.start_link(table_name, [:set, :public])
      eternal_filesystem = Hako.Adapter.ETS.configure(name: table_name, eternal: true)
      {_, config} = eternal_filesystem

      {:ok, pid1} = Hako.Adapter.ETS.start_link(eternal_filesystem)
      :ok = Hako.Adapter.ETS.write(config, "file1.txt", "Content 1", [])
      GenServer.stop(pid1, :normal)
      Process.sleep(10)

      {:ok, pid2} = Hako.Adapter.ETS.start_link(eternal_filesystem)
      :ok = Hako.Adapter.ETS.write(config, "file2.txt", "Content 2", [])
      GenServer.stop(pid2, :normal)
      Process.sleep(10)

      {:ok, _pid3} = Hako.Adapter.ETS.start_link(eternal_filesystem)

      assert {:ok, "Content 1"} = Hako.Adapter.ETS.read(config, "file1.txt")
      assert {:ok, "Content 2"} = Hako.Adapter.ETS.read(config, "file2.txt")

      Eternal.stop(table_name)
    end

    test "eternal tables preserve versioning data across restarts" do
      table_name = :"eternal_versioning_#{System.unique_integer([:positive])}"
      versions_table_name = :"#{table_name}_versions"

      {:ok, _eternal_pid} = Eternal.start_link(table_name, [:set, :public])
      {:ok, _versions_eternal_pid} = Eternal.start_link(versions_table_name, [:set, :public])

      eternal_filesystem = Hako.Adapter.ETS.configure(name: table_name, eternal: true)
      {:ok, pid1} = Hako.Adapter.ETS.start_link(eternal_filesystem)
      {_, config} = eternal_filesystem

      {:ok, v1} =
        Hako.Adapter.ETS.write_version(config, "versioned.txt", "Version 1", [])

      {:ok, _v2} =
        Hako.Adapter.ETS.write_version(config, "versioned.txt", "Version 2", [])

      GenServer.stop(pid1, :normal)
      Process.sleep(10)

      {:ok, _pid2} = Hako.Adapter.ETS.start_link(eternal_filesystem)

      {:ok, versions} = Hako.Adapter.ETS.list_versions(config, "versioned.txt")
      assert length(versions) == 2

      assert {:ok, "Version 1"} = Hako.Adapter.ETS.read_version(config, "versioned.txt", v1)

      Eternal.stop(table_name)
      Eternal.stop(versions_table_name)
    end

    test "non-eternal tables do not survive process termination" do
      table_name = :"regular_survival_#{System.unique_integer([:positive])}"

      regular_filesystem = Hako.Adapter.ETS.configure(name: table_name, eternal: false)
      {:ok, pid} = Hako.Adapter.ETS.start_link(regular_filesystem)
      {_, config} = regular_filesystem

      :ok = Hako.Adapter.ETS.write(config, "temporary.txt", "This will be lost", [])
      assert {:ok, "This will be lost"} = Hako.Adapter.ETS.read(config, "temporary.txt")

      table_ref = config.table
      GenServer.stop(pid, :normal)
      Process.sleep(10)

      assert :undefined = :ets.info(table_ref)
    end

    test "eternal configuration defaults to false" do
      filesystem = Hako.Adapter.ETS.configure(name: :default_eternal_test)
      {_, config} = filesystem
      assert config.eternal == false
    end

    test "eternal configuration can be explicitly set" do
      eternal_fs = Hako.Adapter.ETS.configure(name: :explicit_eternal, eternal: true)
      {_, eternal_config} = eternal_fs
      assert eternal_config.eternal == true

      regular_fs = Hako.Adapter.ETS.configure(name: :explicit_regular, eternal: false)
      {_, regular_config} = regular_fs
      assert regular_config.eternal == false
    end
  end

  # ============================================================================
  # FILE EXISTS EDGE CASES
  # ============================================================================

  describe "file_exists edge cases" do
    test "file_exists for existing file", %{filesystem: fs} do
      :ok = Hako.write(fs, "exists.txt", "content")
      assert {:ok, :exists} = Hako.file_exists(fs, "exists.txt")
    end

    test "file_exists for missing file", %{filesystem: fs} do
      assert {:ok, :missing} = Hako.file_exists(fs, "missing.txt")
    end

    test "file_exists for directory", %{filesystem: fs} do
      :ok = Hako.create_directory(fs, "dir_exists/")
      assert {:ok, :exists} = Hako.file_exists(fs, "dir_exists/")
    end

    test "file_exists in missing parent directory", %{filesystem: fs} do
      assert {:ok, :missing} = Hako.file_exists(fs, "no_such_dir/file.txt")
    end

    test "file_exists after delete", %{filesystem: fs} do
      :ok = Hako.write(fs, "delete_check.txt", "content")
      assert {:ok, :exists} = Hako.file_exists(fs, "delete_check.txt")
      :ok = Hako.delete(fs, "delete_check.txt")
      assert {:ok, :missing} = Hako.file_exists(fs, "delete_check.txt")
    end
  end

  # ============================================================================
  # STAT OPERATIONS
  # ============================================================================

  describe "stat operations" do
    test "stat file returns correct metadata", %{filesystem: fs} do
      {:ok, contents} = Hako.list_contents(fs, ".")

      :ok = Hako.write(fs, "stat_test.txt", "1234567890", visibility: :public)
      {:ok, updated_contents} = Hako.list_contents(fs, ".")

      file_stat =
        Enum.find(
          updated_contents -- contents,
          &match?(%Hako.Stat.File{name: "stat_test.txt"}, &1)
        )

      assert file_stat.name == "stat_test.txt"
      assert file_stat.size == 10
      assert file_stat.visibility == :public
    end

    test "stat directory returns correct metadata", %{filesystem: fs} do
      :ok = Hako.create_directory(fs, "stat_dir/", directory_visibility: :private)
      {:ok, contents} = Hako.list_contents(fs, ".")

      dir_stat = Enum.find(contents, &match?(%Hako.Stat.Dir{name: "stat_dir"}, &1))

      assert dir_stat.name == "stat_dir"
      assert dir_stat.visibility == :private
    end
  end

  # ============================================================================
  # COPY BETWEEN FILESYSTEMS
  # ============================================================================

  describe "copy between filesystems" do
    test "copy between same filesystem", %{filesystem: fs} do
      :ok = Hako.write(fs, "cross_src.txt", "cross content")

      assert :ok =
               Hako.copy_between_filesystem(
                 {fs, "cross_src.txt"},
                 {fs, "cross_dest.txt"}
               )

      assert {:ok, "cross content"} = Hako.read(fs, "cross_dest.txt")
    end

    test "copy between different ETS filesystems manually via read/write" do
      table1 = :"cross_copy_1_#{System.unique_integer([:positive])}"
      table2 = :"cross_copy_2_#{System.unique_integer([:positive])}"

      fs1 = Hako.Adapter.ETS.configure(name: table1)
      fs2 = Hako.Adapter.ETS.configure(name: table2)

      start_supervised!({Hako.Adapter.ETS, fs1}, id: :fs1)
      start_supervised!({Hako.Adapter.ETS, fs2}, id: :fs2)

      :ok = Hako.write(fs1, "source.txt", "original content")

      {:ok, content} = Hako.read(fs1, "source.txt")
      :ok = Hako.write(fs2, "dest.txt", content)

      assert {:ok, "original content"} = Hako.read(fs2, "dest.txt")
    end

    test "copy from missing file returns error", %{filesystem: fs} do
      assert {:error, %Hako.Errors.FileNotFound{}} =
               Hako.copy_between_filesystem(
                 {fs, "nonexistent.txt"},
                 {fs, "dest.txt"}
               )
    end
  end
end
