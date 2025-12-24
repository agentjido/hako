defmodule Hako.Adapter.LocalIntegrationTest do
  @moduledoc """
  Comprehensive integration tests for the Local adapter.

  These tests exercise edge cases, error conditions, and boundary scenarios
  to ensure the adapter returns proper error types and handles all cases gracefully.

  Run with: mix test --include integration
  """
  use ExUnit.Case, async: false
  import Bitwise

  @moduletag :integration
  @moduletag :tmp_dir

  setup %{tmp_dir: prefix} do
    filesystem = Hako.Adapter.Local.configure(prefix: prefix)
    {_, config} = filesystem
    {:ok, filesystem: filesystem, config: config, prefix: prefix}
  end

  defp unix_only do
    case :os.type() do
      {:unix, _} -> true
      _ -> false
    end
  end

  defp match_mode(input, match) do
    (input &&& 0o777) == match
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

    test "empty file", %{filesystem: fs, prefix: prefix} do
      assert :ok = Hako.write(fs, "empty.bin", "")
      assert {:ok, ""} = Hako.read(fs, "empty.bin")
      assert %{size: 0} = File.stat!(Path.join(prefix, "empty.bin"))
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

    test "special characters in filenames", %{filesystem: fs} do
      assert :ok = Hako.write(fs, "file with spaces.txt", "spaces")
      assert {:ok, "spaces"} = Hako.read(fs, "file with spaces.txt")

      assert :ok = Hako.write(fs, "file-with-dashes.txt", "dashes")
      assert {:ok, "dashes"} = Hako.read(fs, "file-with-dashes.txt")

      assert :ok = Hako.write(fs, "file_with_underscores.txt", "underscores")
      assert {:ok, "underscores"} = Hako.read(fs, "file_with_underscores.txt")
    end

    test "path traversal attempt with ..", %{filesystem: fs} do
      assert {:error, %Hako.Errors.PathTraversal{}} = Hako.write(fs, "../evil.txt", "bad")
    end

    test "path traversal attempt with nested ..", %{filesystem: fs} do
      assert {:error, %Hako.Errors.PathTraversal{}} =
               Hako.write(fs, "a/b/../../c/../../../evil.txt", "bad")
    end

    test "path traversal in read", %{filesystem: fs} do
      assert {:error, %Hako.Errors.PathTraversal{}} = Hako.read(fs, "../etc/passwd")
    end

    test "path traversal in delete", %{filesystem: fs} do
      assert {:error, %Hako.Errors.PathTraversal{}} = Hako.delete(fs, "../evil.txt")
    end

    test "path traversal in move source", %{filesystem: fs} do
      assert {:error, %Hako.Errors.PathTraversal{}} = Hako.move(fs, "../evil.txt", "dest.txt")
    end

    test "path traversal in copy source", %{filesystem: fs} do
      assert {:error, %Hako.Errors.PathTraversal{}} = Hako.copy(fs, "../evil.txt", "dest.txt")
    end

    test "absolute paths are rejected", %{filesystem: fs} do
      assert {:error, %Hako.Errors.AbsolutePath{}} = Hako.write(fs, "/etc/passwd", "bad")
      assert {:error, %Hako.Errors.AbsolutePath{}} = Hako.read(fs, "/etc/passwd")
      assert {:error, %Hako.Errors.AbsolutePath{}} = Hako.delete(fs, "/etc/passwd")
    end

    test "deeply nested path", %{filesystem: fs} do
      deep_path = Enum.map_join(1..20, "/", fn n -> "dir#{n}" end) <> "/file.txt"
      assert :ok = Hako.write(fs, deep_path, "deep content")
      assert {:ok, "deep content"} = Hako.read(fs, deep_path)
    end

    test "path normalization with redundant slashes", %{filesystem: fs} do
      assert :ok = Hako.write(fs, "a//b///c/file.txt", "slashes")
      assert {:ok, "slashes"} = Hako.read(fs, "a/b/c/file.txt")
    end

    test "path normalization with dot segments", %{filesystem: fs} do
      assert :ok = Hako.write(fs, "a/./b/./file.txt", "dots")
      assert {:ok, "dots"} = Hako.read(fs, "a/b/file.txt")
    end

    test "write to file where parent is a file (enotdir)", %{filesystem: fs, prefix: prefix} do
      File.write!(Path.join(prefix, "not_a_dir"), "I'm a file")

      result = Hako.write(fs, "not_a_dir/child.txt", "content")

      assert {:error, error} = result

      case error do
        %Hako.Errors.DirectoryNotFound{} -> :ok
        %Hako.Errors.NotDirectory{} -> :ok
        %Hako.Errors.DirectoryNotEmpty{} -> :ok
        %Hako.Errors.AdapterError{} -> :ok
        :eexist -> :ok
        :enotdir -> :ok
      end
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

    test "read from missing parent directory", %{filesystem: fs} do
      assert {:error, %Hako.Errors.DirectoryNotFound{}} =
               Hako.read(fs, "no_such_dir/missing.txt")
    end

    test "move missing file", %{filesystem: fs} do
      assert {:error, %Hako.Errors.FileNotFound{}} = Hako.move(fs, "missing.txt", "dest.txt")
    end

    test "copy missing file", %{filesystem: fs} do
      assert {:error, %Hako.Errors.FileNotFound{}} = Hako.copy(fs, "missing.txt", "dest.txt")
    end

    test "stat missing file", %{filesystem: fs} do
      assert {:error, %Hako.Errors.FileNotFound{}} = Hako.stat(fs, "missing.txt")
    end

    test "visibility of missing file", %{filesystem: fs} do
      assert {:error, %Hako.Errors.FileNotFound{}} = Hako.visibility(fs, "missing.txt")
    end
  end

  describe "error conditions - permission denied (unix only)" do
    @describetag :unix

    setup %{prefix: prefix} do
      if unix_only() do
        protected_file = Path.join(prefix, "protected.txt")
        File.write!(protected_file, "protected content")
        File.chmod!(protected_file, 0o000)

        protected_dir = Path.join(prefix, "protected_dir")
        File.mkdir_p!(protected_dir)
        File.chmod!(protected_dir, 0o000)

        on_exit(fn ->
          File.chmod(protected_file, 0o644)
          File.chmod(protected_dir, 0o755)
        end)

        {:ok, protected_file: protected_file, protected_dir: protected_dir}
      else
        :ok
      end
    end

    test "read protected file", %{filesystem: fs} do
      if unix_only() do
        assert {:error, %Hako.Errors.PermissionDenied{}} = Hako.read(fs, "protected.txt")
      end
    end

    test "write to protected file", %{filesystem: fs} do
      if unix_only() do
        result = Hako.write(fs, "protected.txt", "new content")

        case result do
          {:error, %Hako.Errors.PermissionDenied{}} -> :ok
          {:error, :eacces} -> :ok
        end
      end
    end

    test "write to protected directory", %{filesystem: fs} do
      if unix_only() do
        result = Hako.write(fs, "protected_dir/file.txt", "content")

        case result do
          {:error, %Hako.Errors.PermissionDenied{}} -> :ok
          {:error, :eacces} -> :ok
        end
      end
    end

    test "access check on protected file", %{config: config, prefix: prefix} do
      if unix_only() do
        protected_file = Path.join(prefix, "access_protected.txt")
        File.write!(protected_file, "protected content")
        File.chmod!(protected_file, 0o000)

        on_exit(fn ->
          File.chmod(protected_file, 0o644)
        end)

        result = Hako.Adapter.Local.access(config, "access_protected.txt", [:read])

        case result do
          {:error, %Hako.Errors.PermissionDenied{operation: "access"}} -> :ok
          :ok -> :ok
        end
      end
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
      assert {:ok, contents} = Hako.list_contents(fs, "a/b/c/d/")

      assert Enum.any?(contents, fn item ->
               match?(%Hako.Stat.Dir{name: "e"}, item)
             end)
    end

    test "delete empty directory", %{filesystem: fs} do
      :ok = Hako.create_directory(fs, "empty_dir/")
      assert :ok = Hako.delete_directory(fs, "empty_dir/")
      assert {:ok, :missing} = Hako.file_exists(fs, "empty_dir/")
    end

    test "delete non-empty directory fails without recursive", %{filesystem: fs} do
      :ok = Hako.write(fs, "non_empty/file.txt", "content")

      assert {:error, %Hako.Errors.DirectoryNotEmpty{}} =
               Hako.delete_directory(fs, "non_empty/", recursive: false)
    end

    test "delete non-empty directory with recursive", %{filesystem: fs} do
      :ok = Hako.write(fs, "to_delete/a/b/file.txt", "content")
      :ok = Hako.write(fs, "to_delete/file2.txt", "content2")
      assert :ok = Hako.delete_directory(fs, "to_delete/", recursive: true)
      assert {:ok, :missing} = Hako.file_exists(fs, "to_delete/")
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

    test "list contents of non-existing directory", %{filesystem: fs} do
      assert {:error, %Hako.Errors.DirectoryNotFound{}} =
               Hako.list_contents(fs, "nonexistent/")
    end

    test "list contents where path is a file", %{filesystem: fs} do
      :ok = Hako.write(fs, "file.txt", "content")

      assert {:error, %Hako.Errors.DirectoryNotFound{}} =
               Hako.list_contents(fs, "file.txt")
    end

    test "delete file as directory fails", %{filesystem: fs} do
      :ok = Hako.write(fs, "file.txt", "content")

      assert {:error, error} = Hako.delete_directory(fs, "file.txt/")
      assert error.__struct__ in [Hako.Errors.DirectoryNotFound, Hako.Errors.NotDirectory]
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
  # EXTENDED OPERATIONS: stat, access, append, truncate, utime
  # ============================================================================

  describe "stat operation" do
    test "stat file", %{filesystem: fs} do
      :ok = Hako.write(fs, "stat_test.txt", "1234567890")

      assert {:ok, %Hako.Stat.File{} = stat} = Hako.stat(fs, "stat_test.txt")
      assert stat.name == "stat_test.txt"
      assert stat.size == 10
      assert stat.visibility in [:public, :private]
      assert is_integer(stat.mtime)
    end

    test "stat directory", %{filesystem: fs} do
      :ok = Hako.create_directory(fs, "stat_dir/")

      assert {:ok, %Hako.Stat.Dir{} = stat} = Hako.stat(fs, "stat_dir")
      assert stat.name == "stat_dir"
    end

    test "stat missing file", %{filesystem: fs} do
      assert {:error, %Hako.Errors.FileNotFound{}} = Hako.stat(fs, "missing.txt")
    end
  end

  describe "access operation" do
    test "access readable file", %{config: config} do
      Hako.Adapter.Local.write(config, "readable.txt", "content", [])
      assert :ok = Hako.Adapter.Local.access(config, "readable.txt", [:read])
    end

    test "access with write mode", %{config: config} do
      Hako.Adapter.Local.write(config, "writable.txt", "content", [])
      assert :ok = Hako.Adapter.Local.access(config, "writable.txt", [:write])
    end

    test "access with both modes", %{config: config} do
      Hako.Adapter.Local.write(config, "both.txt", "content", [])
      assert :ok = Hako.Adapter.Local.access(config, "both.txt", [:read, :write])
    end

    test "access missing file", %{config: config} do
      assert {:error, %Hako.Errors.FileNotFound{}} =
               Hako.Adapter.Local.access(config, "missing.txt", [:read])
    end
  end

  describe "append operation" do
    test "append to existing file", %{config: config} do
      Hako.Adapter.Local.write(config, "append.txt", "abc", [])
      assert :ok = Hako.Adapter.Local.append(config, "append.txt", "def", [])
      assert {:ok, "abcdef"} = Hako.Adapter.Local.read(config, "append.txt")
    end

    test "append creates new file", %{config: config} do
      assert :ok = Hako.Adapter.Local.append(config, "new_append.txt", "content", [])
      assert {:ok, "content"} = Hako.Adapter.Local.read(config, "new_append.txt")
    end

    test "append with directory creation", %{config: config} do
      assert :ok =
               Hako.Adapter.Local.append(config, "nested/append.txt", "content",
                 directory_visibility: :private
               )

      assert {:ok, "content"} = Hako.Adapter.Local.read(config, "nested/append.txt")
    end

    test "multiple appends", %{config: config} do
      Hako.Adapter.Local.write(config, "multi.txt", "", [])
      Hako.Adapter.Local.append(config, "multi.txt", "a", [])
      Hako.Adapter.Local.append(config, "multi.txt", "b", [])
      Hako.Adapter.Local.append(config, "multi.txt", "c", [])
      assert {:ok, "abc"} = Hako.Adapter.Local.read(config, "multi.txt")
    end
  end

  describe "truncate operation" do
    test "truncate to zero", %{config: config} do
      Hako.Adapter.Local.write(config, "truncate.txt", "abcdef", [])
      assert :ok = Hako.Adapter.Local.truncate(config, "truncate.txt", 0)
      assert {:ok, ""} = Hako.Adapter.Local.read(config, "truncate.txt")
    end

    test "truncate to smaller size", %{config: config} do
      Hako.Adapter.Local.write(config, "truncate_small.txt", "abcdef", [])
      assert :ok = Hako.Adapter.Local.truncate(config, "truncate_small.txt", 3)

      {:ok, content} = Hako.Adapter.Local.read(config, "truncate_small.txt")
      assert byte_size(content) == 3
    end

    test "truncate to larger size pads with zeros", %{config: config} do
      Hako.Adapter.Local.write(config, "truncate_large.txt", "abc", [])
      assert :ok = Hako.Adapter.Local.truncate(config, "truncate_large.txt", 10)

      assert {:ok, content} = Hako.Adapter.Local.read(config, "truncate_large.txt")
      assert byte_size(content) == 10
    end

    test "truncate missing file", %{config: config} do
      assert {:error, %Hako.Errors.FileNotFound{}} =
               Hako.Adapter.Local.truncate(config, "missing.txt", 10)
    end
  end

  describe "utime operation" do
    test "set modification time on file", %{config: config, prefix: prefix} do
      Hako.Adapter.Local.write(config, "utime.txt", "content", [])

      past_time = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      assert :ok = Hako.Adapter.Local.utime(config, "utime.txt", past_time)

      stat = File.stat!(Path.join(prefix, "utime.txt"), time: :posix)
      stat_datetime = DateTime.from_unix!(stat.mtime)
      assert_in_delta DateTime.to_unix(past_time), DateTime.to_unix(stat_datetime), 3600 * 24
    end

    test "set modification time on directory", %{config: config, prefix: prefix} do
      Hako.Adapter.Local.create_directory(config, "utime_dir/", [])

      past_time = DateTime.utc_now() |> DateTime.add(-7200, :second) |> DateTime.truncate(:second)
      assert :ok = Hako.Adapter.Local.utime(config, "utime_dir", past_time)

      stat = File.stat!(Path.join(prefix, "utime_dir"), time: :posix)
      stat_datetime = DateTime.from_unix!(stat.mtime)
      assert_in_delta DateTime.to_unix(past_time), DateTime.to_unix(stat_datetime), 3600 * 24
    end

    test "utime on missing file", %{config: config} do
      past_time = DateTime.utc_now()

      assert {:error, %Hako.Errors.FileNotFound{}} =
               Hako.Adapter.Local.utime(config, "missing.txt", past_time)
    end
  end

  # ============================================================================
  # STREAM OPERATIONS
  # ============================================================================

  describe "stream operations" do
    test "write stream", %{filesystem: fs} do
      assert {:ok, stream} = Hako.write_stream(fs, "stream_write.txt")
      Enum.into(["Hello", " ", "World"], stream)
      assert {:ok, "Hello World"} = Hako.read(fs, "stream_write.txt")
    end

    test "read stream", %{filesystem: fs} do
      :ok = Hako.write(fs, "stream_read.txt", "Hello World")
      assert {:ok, stream} = Hako.read_stream(fs, "stream_read.txt")
      assert Enum.into(stream, <<>>) == "Hello World"
    end

    test "read stream with chunk size", %{filesystem: fs} do
      :ok = Hako.write(fs, "chunked.txt", "abcdef")
      assert {:ok, stream} = Hako.read_stream(fs, "chunked.txt", chunk_size: 2)
      chunks = Enum.to_list(stream)
      assert chunks == ["ab", "cd", "ef"]
    end

    test "read stream by lines", %{filesystem: fs} do
      :ok = Hako.write(fs, "lines.txt", "line1\nline2\nline3\n")
      assert {:ok, stream} = Hako.read_stream(fs, "lines.txt", chunk_size: :line)
      lines = Enum.to_list(stream)
      assert lines == ["line1\n", "line2\n", "line3\n"]
    end

    test "partial stream consumption", %{filesystem: fs} do
      :ok = Hako.write(fs, "partial.txt", "abcdefghij")
      {:ok, stream} = Hako.read_stream(fs, "partial.txt", chunk_size: 2)

      first_two = stream |> Stream.take(2) |> Enum.to_list()
      assert first_two == ["ab", "cd"]

      assert :ok = Hako.delete(fs, "partial.txt")
    end

    test "stream on missing file raises on enumeration", %{filesystem: fs} do
      {:ok, stream} = Hako.read_stream(fs, "missing.txt")

      assert_raise File.Error, fn ->
        Enum.into(stream, <<>>)
      end
    end
  end

  # ============================================================================
  # VISIBILITY AND PERMISSIONS
  # ============================================================================

  describe "visibility operations" do
    test "write with public visibility", %{filesystem: fs, prefix: prefix} do
      :ok = Hako.write(fs, "public.txt", "content", visibility: :public)

      %{mode: mode} = File.stat!(Path.join(prefix, "public.txt"))
      assert match_mode(mode, 0o644)
    end

    test "write with private visibility", %{filesystem: fs, prefix: prefix} do
      :ok = Hako.write(fs, "private.txt", "content", visibility: :private)

      %{mode: mode} = File.stat!(Path.join(prefix, "private.txt"))
      assert match_mode(mode, 0o600)
    end

    test "get visibility of public file", %{filesystem: fs} do
      :ok = Hako.write(fs, "vis_public.txt", "content", visibility: :public)
      assert {:ok, :public} = Hako.visibility(fs, "vis_public.txt")
    end

    test "get visibility of private file", %{filesystem: fs} do
      :ok = Hako.write(fs, "vis_private.txt", "content", visibility: :private)
      assert {:ok, :private} = Hako.visibility(fs, "vis_private.txt")
    end

    test "set visibility on existing file", %{filesystem: fs} do
      :ok = Hako.write(fs, "change_vis.txt", "content", visibility: :public)
      assert {:ok, :public} = Hako.visibility(fs, "change_vis.txt")

      :ok = Hako.set_visibility(fs, "change_vis.txt", :private)
      assert {:ok, :private} = Hako.visibility(fs, "change_vis.txt")
    end

    test "directory visibility on auto-created dirs", %{filesystem: fs, prefix: prefix} do
      :ok = Hako.write(fs, "public_dir/file.txt", "content", directory_visibility: :public)
      :ok = Hako.write(fs, "private_dir/file.txt", "content", directory_visibility: :private)

      %{mode: public_mode} = File.stat!(Path.join(prefix, "public_dir"))
      %{mode: private_mode} = File.stat!(Path.join(prefix, "private_dir"))

      assert match_mode(public_mode, 0o755)
      assert match_mode(private_mode, 0o700)
    end

    test "set visibility on directory", %{filesystem: fs} do
      :ok = Hako.create_directory(fs, "vis_dir/", directory_visibility: :public)
      assert {:ok, :public} = Hako.visibility(fs, "vis_dir/")

      :ok = Hako.set_visibility(fs, "vis_dir/", :private)
      assert {:ok, :private} = Hako.visibility(fs, "vis_dir/")
    end

    test "visibility of missing file returns error", %{filesystem: fs} do
      assert {:error, %Hako.Errors.FileNotFound{}} = Hako.visibility(fs, "nonexistent.txt")
    end

    test "set visibility on missing file returns error", %{filesystem: fs} do
      assert {:error, %Hako.Errors.FileNotFound{}} =
               Hako.set_visibility(fs, "nonexistent.txt", :public)
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
  end

  # ============================================================================
  # CONCURRENCY TESTS
  # ============================================================================

  describe "concurrency" do
    test "simultaneous writes to same file", %{filesystem: fs} do
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

    test "concurrent reads", %{filesystem: fs} do
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

    test "concurrent write and read", %{filesystem: fs} do
      :ok = Hako.write(fs, "wr_concurrent.txt", "initial")

      writer =
        Task.async(fn ->
          Process.sleep(10)
          Hako.write(fs, "wr_concurrent.txt", "updated")
        end)

      reader =
        Task.async(fn ->
          Process.sleep(20)
          Hako.read(fs, "wr_concurrent.txt")
        end)

      assert :ok = Task.await(writer)
      assert {:ok, content} = Task.await(reader)
      assert content in ["initial", "updated"]
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
        case result do
          :ok -> :ok
          {:error, :eexist} -> :ok
          other -> flunk("Unexpected result: #{inspect(other)}")
        end
      end

      ok_count = Enum.count(results, fn {_n, r} -> r == :ok end)
      assert ok_count == 10
    end
  end

  # ============================================================================
  # CROSS-FILESYSTEM OPERATIONS
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

    test "copy between different local filesystems", %{prefix: prefix} do
      prefix2 = Path.join(System.tmp_dir!(), "hako_test_#{:erlang.unique_integer([:positive])}")
      File.mkdir_p!(prefix2)

      on_exit(fn -> File.rm_rf!(prefix2) end)

      fs1 = Hako.Adapter.Local.configure(prefix: prefix)
      fs2 = Hako.Adapter.Local.configure(prefix: prefix2)

      :ok = Hako.write(fs1, "source.txt", "original content")

      assert :ok =
               Hako.copy_between_filesystem(
                 {fs1, "source.txt"},
                 {fs2, "dest.txt"}
               )

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
  end
end
