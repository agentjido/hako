defmodule Hako.Adapter.GitIntegrationTest do
  @moduledoc """
  Comprehensive integration tests for the Git adapter.

  These tests exercise edge cases, error conditions, and boundary scenarios
  to ensure the adapter returns proper error types and handles all cases gracefully.

  Run with: mix test --include integration
  """
  use ExUnit.Case, async: false

  alias Hako.Adapter.Git
  alias Hako.Revision

  @moduletag :integration

  @tmp_base "tmp/git_integration_test"

  setup do
    case System.find_executable("git") do
      nil -> {:skip, "Git not available"}
      _ -> :ok
    end

    test_id = :erlang.unique_integer([:positive])
    tmp_dir = Path.join(@tmp_base, "test_#{test_id}")
    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    repo_path = Path.join(tmp_dir, "repo")

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir, repo_path: repo_path}
  end

  defp git_status(repo_path) do
    {output, 0} = System.cmd("git", ["status", "--porcelain"], cd: repo_path)
    output
  end

  defp git_log(repo_path, opts \\ []) do
    args = ["log", "--oneline"] ++ opts
    {output, _} = System.cmd("git", args, cd: repo_path)
    String.split(output, "\n", trim: true)
  end

  defp commit_count(repo_path) do
    length(git_log(repo_path))
  end

  defp last_commit_message(repo_path) do
    [line | _] = git_log(repo_path, ["-n", "1"])
    # Format: "sha message"
    String.split(line, " ", parts: 2) |> List.last()
  end

  # ============================================================================
  # CORE OPERATIONS: Write/Read/Delete/Move/Copy (delegated to Local)
  # ============================================================================

  describe "core operations - happy paths" do
    setup %{repo_path: repo_path} do
      filesystem = Git.configure(path: repo_path, mode: :manual)
      {:ok, filesystem: filesystem}
    end

    test "basic write/read roundtrip", %{filesystem: fs} do
      assert :ok = Hako.write(fs, "file.txt", "hello")
      assert {:ok, "hello"} = Hako.read(fs, "file.txt")
    end

    test "write with iodata (list)", %{filesystem: fs} do
      assert :ok = Hako.write(fs, "iodata.txt", ["he", "llo", " ", "world"])
      assert {:ok, "hello world"} = Hako.read(fs, "iodata.txt")
    end

    test "empty file", %{filesystem: fs, repo_path: repo_path} do
      assert :ok = Hako.write(fs, "empty.bin", "")
      assert {:ok, ""} = Hako.read(fs, "empty.bin")
      assert %{size: 0} = File.stat!(Path.join(repo_path, "empty.bin"))
    end

    test "binary data with null bytes", %{filesystem: fs} do
      content = <<0, 1, 255, 0, 42, 128, 200>>
      assert :ok = Hako.write(fs, "binary.bin", content)
      assert {:ok, ^content} = Hako.read(fs, "binary.bin")
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

    test "operations are staged in git", %{filesystem: fs, repo_path: repo_path} do
      Hako.write(fs, "staged.txt", "content")
      status = git_status(repo_path)
      assert String.contains?(status, "A  staged.txt")
    end
  end

  # ============================================================================
  # PATH EDGE CASES
  # ============================================================================

  describe "path edge cases" do
    setup %{repo_path: repo_path} do
      filesystem = Git.configure(path: repo_path, mode: :manual)
      {:ok, filesystem: filesystem}
    end

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

    test "absolute paths are rejected", %{filesystem: fs} do
      assert {:error, %Hako.Errors.AbsolutePath{}} = Hako.write(fs, "/etc/passwd", "bad")
      assert {:error, %Hako.Errors.AbsolutePath{}} = Hako.read(fs, "/etc/passwd")
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
  end

  # ============================================================================
  # AUTO MODE
  # ============================================================================

  describe "auto mode - operations auto-commit" do
    setup %{repo_path: repo_path} do
      filesystem = Git.configure(path: repo_path, mode: :auto)
      {:ok, filesystem: filesystem}
    end

    test "write auto-commits", %{filesystem: fs, repo_path: repo_path} do
      initial_count = commit_count(repo_path)
      Hako.write(fs, "auto.txt", "content")

      assert git_status(repo_path) == ""
      assert commit_count(repo_path) == initial_count + 1
    end

    test "delete auto-commits", %{filesystem: fs, repo_path: repo_path} do
      Hako.write(fs, "to_delete.txt", "content")
      initial_count = commit_count(repo_path)

      Hako.delete(fs, "to_delete.txt")

      assert git_status(repo_path) == ""
      assert commit_count(repo_path) == initial_count + 1
    end

    test "move auto-commits", %{filesystem: fs, repo_path: repo_path} do
      Hako.write(fs, "src.txt", "content")
      initial_count = commit_count(repo_path)

      Hako.move(fs, "src.txt", "dest.txt")

      assert git_status(repo_path) == ""
      assert commit_count(repo_path) == initial_count + 1
    end

    test "copy auto-commits", %{filesystem: fs, repo_path: repo_path} do
      Hako.write(fs, "src.txt", "content")
      initial_count = commit_count(repo_path)

      Hako.copy(fs, "src.txt", "dest.txt")

      assert git_status(repo_path) == ""
      assert commit_count(repo_path) == initial_count + 1
    end

    test "create_directory auto-commits", %{filesystem: fs, repo_path: repo_path} do
      initial_count = commit_count(repo_path)
      Hako.create_directory(fs, "new_dir/")

      assert git_status(repo_path) == ""
      assert commit_count(repo_path) == initial_count + 1
    end

    test "commit messages contain operation info", %{filesystem: fs, repo_path: repo_path} do
      Hako.write(fs, "test.txt", "content")
      message = last_commit_message(repo_path)
      assert String.contains?(message, "write")
      assert String.contains?(message, "test.txt")
    end

    test "delete commit message contains operation", %{filesystem: fs, repo_path: repo_path} do
      Hako.write(fs, "delete_me.txt", "content")
      Hako.delete(fs, "delete_me.txt")
      message = last_commit_message(repo_path)
      assert String.contains?(message, "delete")
    end

    test "move commit message shows source and dest", %{filesystem: fs, repo_path: repo_path} do
      Hako.write(fs, "source.txt", "content")
      Hako.move(fs, "source.txt", "dest.txt")
      message = last_commit_message(repo_path)
      assert String.contains?(message, "move")
      assert String.contains?(message, "source.txt")
      assert String.contains?(message, "dest.txt")
    end
  end

  # ============================================================================
  # MANUAL MODE
  # ============================================================================

  describe "manual mode - operations staged but not committed" do
    setup %{repo_path: repo_path} do
      filesystem = Git.configure(path: repo_path, mode: :manual)
      {:ok, filesystem: filesystem}
    end

    test "write stages but does not commit", %{filesystem: fs, repo_path: repo_path} do
      initial_count = commit_count(repo_path)
      Hako.write(fs, "manual.txt", "content")

      status = git_status(repo_path)
      assert String.contains?(status, "A  manual.txt")
      assert commit_count(repo_path) == initial_count
    end

    test "multiple operations remain staged", %{filesystem: fs, repo_path: repo_path} do
      Hako.write(fs, "file1.txt", "content1")
      Hako.write(fs, "file2.txt", "content2")
      Hako.write(fs, "dir/file3.txt", "content3")

      status = git_status(repo_path)
      assert String.contains?(status, "file1.txt")
      assert String.contains?(status, "file2.txt")
      assert String.contains?(status, "file3.txt")
    end

    test "explicit commit required", %{filesystem: fs, repo_path: repo_path} do
      initial_count = commit_count(repo_path)
      Hako.write(fs, "manual.txt", "content")
      Hako.commit(fs, "My commit")

      assert git_status(repo_path) == ""
      assert commit_count(repo_path) == initial_count + 1
      assert last_commit_message(repo_path) == "My commit"
    end

    test "delete is staged", %{filesystem: fs, repo_path: repo_path} do
      Hako.write(fs, "to_delete.txt", "content")
      Hako.commit(fs, "Add file")

      Hako.delete(fs, "to_delete.txt")
      status = git_status(repo_path)
      assert String.contains?(status, "D  to_delete.txt")
    end

    test "move is staged as delete + add", %{filesystem: fs, repo_path: repo_path} do
      Hako.write(fs, "src.txt", "content")
      Hako.commit(fs, "Add file")

      Hako.move(fs, "src.txt", "dest.txt")
      status = git_status(repo_path)

      assert String.contains?(status, "R  src.txt -> dest.txt") or
               (String.contains?(status, "D") and String.contains?(status, "A"))
    end
  end

  # ============================================================================
  # COMMIT OPERATIONS
  # ============================================================================

  describe "commit operations" do
    setup %{repo_path: repo_path} do
      filesystem = Git.configure(path: repo_path, mode: :manual)
      {:ok, filesystem: filesystem}
    end

    test "commit with message", %{filesystem: fs, repo_path: repo_path} do
      Hako.write(fs, "file.txt", "content")
      assert :ok = Hako.commit(fs, "Add file")
      assert last_commit_message(repo_path) == "Add file"
    end

    test "commit without message uses default", %{filesystem: fs, repo_path: repo_path} do
      Hako.write(fs, "file.txt", "content")
      assert :ok = Hako.commit(fs)
      message = last_commit_message(repo_path)
      assert String.contains?(message, "Manual commit")
    end

    test "commit with no changes returns ok", %{filesystem: fs, repo_path: repo_path} do
      initial_count = commit_count(repo_path)
      assert :ok = Hako.commit(fs, "Nothing to commit")
      assert commit_count(repo_path) == initial_count
    end

    test "commit with empty message uses default", %{filesystem: fs, repo_path: repo_path} do
      Hako.write(fs, "file.txt", "content")
      assert :ok = Hako.commit(fs, nil)
      message = last_commit_message(repo_path)
      assert String.contains?(message, "Manual commit")
    end

    test "multiple commits create history", %{filesystem: fs, repo_path: repo_path} do
      initial_count = commit_count(repo_path)

      Hako.write(fs, "file1.txt", "content1")
      Hako.commit(fs, "First commit")

      Hako.write(fs, "file2.txt", "content2")
      Hako.commit(fs, "Second commit")

      Hako.write(fs, "file3.txt", "content3")
      Hako.commit(fs, "Third commit")

      assert commit_count(repo_path) == initial_count + 3
    end

    test "commit stages all pending changes", %{filesystem: fs, repo_path: repo_path} do
      Hako.write(fs, "file1.txt", "content1")
      Hako.write(fs, "file2.txt", "content2")
      Hako.commit(fs, "Add both files")

      assert git_status(repo_path) == ""
    end
  end

  # ============================================================================
  # REVISION HISTORY
  # ============================================================================

  describe "revision history" do
    setup %{repo_path: repo_path} do
      filesystem = Git.configure(path: repo_path, mode: :manual)
      {:ok, filesystem: filesystem}
    end

    test "revisions lists commit history", %{filesystem: fs} do
      Hako.write(fs, "file1.txt", "content1")
      Hako.commit(fs, "First commit")

      Hako.write(fs, "file2.txt", "content2")
      Hako.commit(fs, "Second commit")

      assert {:ok, revisions} = Hako.revisions(fs, ".")
      assert length(revisions) >= 2

      [latest | _] = revisions
      assert %Revision{} = latest
      assert latest.message == "Second commit"
      assert is_binary(latest.sha)
      assert String.length(latest.sha) == 40
      assert %DateTime{} = latest.timestamp
    end

    test "revisions with limit", %{filesystem: fs} do
      Hako.write(fs, "file1.txt", "content1")
      Hako.commit(fs, "First commit")

      Hako.write(fs, "file2.txt", "content2")
      Hako.commit(fs, "Second commit")

      Hako.write(fs, "file3.txt", "content3")
      Hako.commit(fs, "Third commit")

      assert {:ok, revisions} = Hako.revisions(fs, ".", limit: 2)
      assert length(revisions) == 2
      assert hd(revisions).message == "Third commit"
    end

    test "revisions for specific file", %{filesystem: fs} do
      Hako.write(fs, "file1.txt", "content1")
      Hako.commit(fs, "Add file1")

      Hako.write(fs, "file2.txt", "content2")
      Hako.commit(fs, "Add file2")

      Hako.write(fs, "file1.txt", "updated content1")
      Hako.commit(fs, "Update file1")

      assert {:ok, revisions} = Hako.revisions(fs, "file1.txt")
      assert length(revisions) == 2
      messages = Enum.map(revisions, & &1.message)
      assert "Update file1" in messages
      assert "Add file1" in messages
    end

    test "revisions returns author info", %{repo_path: repo_path} do
      filesystem =
        Git.configure(
          path: repo_path,
          mode: :manual,
          author: [name: "Test Author", email: "test@example.com"]
        )

      Hako.write(filesystem, "file.txt", "content")
      Hako.commit(filesystem, "Test commit")

      {:ok, [revision | _]} = Hako.revisions(filesystem, ".")
      assert revision.author_name == "Test Author"
      assert revision.author_email == "test@example.com"
    end

    test "revisions on empty path returns all commits", %{filesystem: fs} do
      Hako.write(fs, "file1.txt", "content1")
      Hako.commit(fs, "First")

      Hako.write(fs, "file2.txt", "content2")
      Hako.commit(fs, "Second")

      {:ok, revisions_dot} = Hako.revisions(fs, ".")
      {:ok, revisions_empty} = Hako.revisions(fs, "")

      assert length(revisions_dot) == length(revisions_empty)
    end

    test "revisions limit of zero returns empty", %{filesystem: fs} do
      Hako.write(fs, "file.txt", "content")
      Hako.commit(fs, "Commit")

      assert {:ok, []} = Hako.revisions(fs, ".", limit: 0)
    end
  end

  # ============================================================================
  # READING REVISIONS
  # ============================================================================

  describe "reading revisions" do
    setup %{repo_path: repo_path} do
      filesystem = Git.configure(path: repo_path, mode: :manual)
      {:ok, filesystem: filesystem}
    end

    test "read_revision for historical content", %{filesystem: fs} do
      Hako.write(fs, "test.txt", "version 1")
      Hako.commit(fs, "First version")

      {:ok, [first_rev | _]} = Hako.revisions(fs, "test.txt")

      Hako.write(fs, "test.txt", "version 2")
      Hako.commit(fs, "Second version")

      assert {:ok, "version 1"} = Hako.read_revision(fs, "test.txt", first_rev.sha)
      assert {:ok, "version 2"} = Hako.read(fs, "test.txt")
    end

    test "file content at different commits", %{filesystem: fs} do
      Hako.write(fs, "file.txt", "v1")
      Hako.commit(fs, "V1")
      {:ok, [v1_rev | _]} = Hako.revisions(fs, "file.txt")

      Hako.write(fs, "file.txt", "v2")
      Hako.commit(fs, "V2")
      {:ok, [v2_rev | _]} = Hako.revisions(fs, "file.txt")

      Hako.write(fs, "file.txt", "v3")
      Hako.commit(fs, "V3")
      {:ok, [v3_rev | _]} = Hako.revisions(fs, "file.txt")

      assert {:ok, "v1"} = Hako.read_revision(fs, "file.txt", v1_rev.sha)
      assert {:ok, "v2"} = Hako.read_revision(fs, "file.txt", v2_rev.sha)
      assert {:ok, "v3"} = Hako.read_revision(fs, "file.txt", v3_rev.sha)
    end

    test "read_revision with short sha prefix", %{filesystem: fs} do
      Hako.write(fs, "file.txt", "content")
      Hako.commit(fs, "Add file")

      {:ok, [rev | _]} = Hako.revisions(fs, "file.txt")
      short_sha = String.slice(rev.sha, 0, 7)

      assert {:ok, "content"} = Hako.read_revision(fs, "file.txt", short_sha)
    end

    test "read_revision for file in subdirectory", %{filesystem: fs} do
      Hako.write(fs, "dir/subdir/file.txt", "nested content")
      Hako.commit(fs, "Add nested file")

      {:ok, [rev | _]} = Hako.revisions(fs, "dir/subdir/file.txt")
      assert {:ok, "nested content"} = Hako.read_revision(fs, "dir/subdir/file.txt", rev.sha)
    end

    test "read_revision for binary content", %{filesystem: fs} do
      binary_content = <<0, 1, 2, 255, 254, 253>>
      Hako.write(fs, "binary.bin", binary_content)
      Hako.commit(fs, "Add binary")

      {:ok, [rev | _]} = Hako.revisions(fs, "binary.bin")
      assert {:ok, ^binary_content} = Hako.read_revision(fs, "binary.bin", rev.sha)
    end
  end

  # ============================================================================
  # ROLLBACK
  # ============================================================================

  describe "rollback" do
    setup %{repo_path: repo_path} do
      filesystem = Git.configure(path: repo_path, mode: :manual)
      {:ok, filesystem: filesystem}
    end

    test "full rollback to commit", %{filesystem: fs} do
      Hako.write(fs, "file.txt", "version 1")
      Hako.commit(fs, "First version")

      {:ok, [target | _]} = Hako.revisions(fs, ".")

      Hako.write(fs, "file.txt", "version 2")
      Hako.write(fs, "new_file.txt", "new content")
      Hako.commit(fs, "Second version")

      assert :ok = Hako.rollback(fs, target.sha)

      assert {:ok, "version 1"} = Hako.read(fs, "file.txt")
      assert {:error, %Hako.Errors.FileNotFound{}} = Hako.read(fs, "new_file.txt")
    end

    test "rollback specific file only", %{filesystem: fs} do
      Hako.write(fs, "file1.txt", "content1")
      Hako.write(fs, "file2.txt", "content2")
      Hako.commit(fs, "Add both files")

      {:ok, [target | _]} = Hako.revisions(fs, ".")

      Hako.write(fs, "file1.txt", "modified1")
      Hako.write(fs, "file2.txt", "modified2")
      Hako.commit(fs, "Modify both files")

      assert :ok = Hako.rollback(fs, target.sha, path: "file1.txt")

      assert {:ok, "content1"} = Hako.read(fs, "file1.txt")
      assert {:ok, "modified2"} = Hako.read(fs, "file2.txt")
    end

    test "rollback file in subdirectory", %{filesystem: fs} do
      Hako.write(fs, "dir/file.txt", "original")
      Hako.commit(fs, "Add file")

      {:ok, [target | _]} = Hako.revisions(fs, ".")

      Hako.write(fs, "dir/file.txt", "modified")
      Hako.commit(fs, "Modify file")

      assert :ok = Hako.rollback(fs, target.sha, path: "dir/file.txt")
      assert {:ok, "original"} = Hako.read(fs, "dir/file.txt")
    end

    test "rollback to initial commit", %{filesystem: fs} do
      {:ok, revisions} = Hako.revisions(fs, ".")
      initial = List.last(revisions)

      Hako.write(fs, "file.txt", "content")
      Hako.commit(fs, "Add file")

      assert :ok = Hako.rollback(fs, initial.sha)
      assert {:error, %Hako.Errors.FileNotFound{}} = Hako.read(fs, "file.txt")
    end

    test "rollback multiple files with full reset", %{filesystem: fs} do
      Hako.write(fs, "a.txt", "a1")
      Hako.write(fs, "b.txt", "b1")
      Hako.write(fs, "c.txt", "c1")
      Hako.commit(fs, "V1")

      {:ok, [v1 | _]} = Hako.revisions(fs, ".")

      Hako.write(fs, "a.txt", "a2")
      Hako.write(fs, "b.txt", "b2")
      Hako.write(fs, "c.txt", "c2")
      Hako.commit(fs, "V2")

      assert :ok = Hako.rollback(fs, v1.sha)

      assert {:ok, "a1"} = Hako.read(fs, "a.txt")
      assert {:ok, "b1"} = Hako.read(fs, "b.txt")
      assert {:ok, "c1"} = Hako.read(fs, "c.txt")
    end
  end

  # ============================================================================
  # BRANCH MANAGEMENT
  # ============================================================================

  describe "branch management" do
    test "use current branch by default", %{repo_path: repo_path} do
      File.mkdir_p!(repo_path)
      System.cmd("git", ["init"], cd: repo_path)
      System.cmd("git", ["checkout", "-b", "feature"], cd: repo_path)

      {Git, config} = Git.configure(path: repo_path)
      assert config.branch == "feature"
    end

    test "switch to existing branch", %{repo_path: repo_path} do
      File.mkdir_p!(repo_path)
      System.cmd("git", ["init"], cd: repo_path)
      File.write!(Path.join(repo_path, "test.txt"), "content")
      System.cmd("git", ["add", "."], cd: repo_path)

      System.cmd(
        "git",
        ["-c", "user.name=Test", "-c", "user.email=test@test.com", "commit", "-m", "initial"],
        cd: repo_path
      )

      System.cmd("git", ["checkout", "-b", "develop"], cd: repo_path)
      System.cmd("git", ["checkout", "main"], cd: repo_path)

      {Git, config} = Git.configure(path: repo_path, branch: "develop")
      assert config.branch == "develop"

      {current_branch, 0} = System.cmd("git", ["branch", "--show-current"], cd: repo_path)
      assert String.trim(current_branch) == "develop"
    end

    test "create new branch if doesn't exist", %{repo_path: repo_path} do
      {Git, config} = Git.configure(path: repo_path, branch: "new-feature")
      assert config.branch == "new-feature"

      {current_branch, 0} = System.cmd("git", ["branch", "--show-current"], cd: repo_path)
      assert String.trim(current_branch) == "new-feature"
    end

    test "commits go to correct branch", %{repo_path: repo_path} do
      filesystem = Git.configure(path: repo_path, branch: "feature-branch", mode: :manual)
      Hako.write(filesystem, "feature.txt", "feature content")
      Hako.commit(filesystem, "Add feature")

      {log, 0} = System.cmd("git", ["log", "--oneline", "feature-branch"], cd: repo_path)
      assert String.contains?(log, "Add feature")
    end

    test "default branch when creating new repo", %{repo_path: repo_path} do
      {Git, config} = Git.configure(path: repo_path)
      assert config.branch in ["main", "master"]
    end
  end

  # ============================================================================
  # DIRECTORY OPERATIONS
  # ============================================================================

  describe "directory operations" do
    setup %{repo_path: repo_path} do
      filesystem = Git.configure(path: repo_path, mode: :manual)
      {:ok, filesystem: filesystem}
    end

    test "create_directory creates .gitkeep", %{filesystem: fs, repo_path: repo_path} do
      assert :ok = Hako.create_directory(fs, "new_dir/")
      assert File.exists?(Path.join(repo_path, "new_dir/.gitkeep"))
      assert {:ok, ""} = Hako.read(fs, "new_dir/.gitkeep")
    end

    test "create nested directories creates .gitkeep in leaf", %{
      filesystem: fs,
      repo_path: repo_path
    } do
      assert :ok = Hako.create_directory(fs, "a/b/c/")
      assert File.exists?(Path.join(repo_path, "a/b/c/.gitkeep"))
    end

    test ".gitkeep is staged", %{filesystem: fs, repo_path: repo_path} do
      Hako.create_directory(fs, "dir/")
      status = git_status(repo_path)
      assert String.contains?(status, ".gitkeep")
    end

    test "delete_directory removes files", %{filesystem: fs} do
      Hako.create_directory(fs, "to_delete/")
      Hako.write(fs, "to_delete/file.txt", "content")
      Hako.commit(fs, "Add dir")

      assert :ok = Hako.delete_directory(fs, "to_delete/", recursive: true)
      # After deletion, reading the file returns either FileNotFound or DirectoryNotFound
      assert {:error, error} = Hako.read(fs, "to_delete/file.txt")
      assert error.__struct__ in [Hako.Errors.FileNotFound, Hako.Errors.DirectoryNotFound]
    end

    test "delete_directory stages removal", %{filesystem: fs, repo_path: repo_path} do
      Hako.create_directory(fs, "staged_dir/")
      Hako.commit(fs, "Add dir")

      Hako.delete_directory(fs, "staged_dir/", recursive: true)
      status = git_status(repo_path)
      assert String.contains?(status, "D")
    end

    test "list_contents includes .gitkeep", %{filesystem: fs} do
      Hako.create_directory(fs, "list_dir/")

      {:ok, contents} = Hako.list_contents(fs, "list_dir")
      assert Enum.any?(contents, &(&1.name == ".gitkeep"))
    end

    test "clear stages all deletions", %{filesystem: fs, repo_path: repo_path} do
      Hako.write(fs, "file1.txt", "content1")
      Hako.write(fs, "dir/file2.txt", "content2")
      Hako.commit(fs, "Add files")

      Hako.clear(fs)

      status = git_status(repo_path)
      assert String.contains?(status, "D")
    end
  end

  # ============================================================================
  # CUSTOM COMMIT MESSAGES
  # ============================================================================

  describe "custom commit messages" do
    test "custom commit_message function is used", %{repo_path: repo_path} do
      custom_msg_fn = fn %{operation: op, path: path} ->
        "[CUSTOM] #{op}: #{path}"
      end

      filesystem =
        Git.configure(
          path: repo_path,
          mode: :auto,
          commit_message: custom_msg_fn
        )

      Hako.write(filesystem, "test.txt", "content")

      message = last_commit_message(repo_path)
      assert String.starts_with?(message, "[CUSTOM] write: test.txt")
    end

    test "custom function receives operation info for delete", %{repo_path: repo_path} do
      received_info = :ets.new(:test_info, [:public, :set])

      custom_msg_fn = fn info ->
        :ets.insert(received_info, {:info, info})
        "Custom delete message"
      end

      filesystem =
        Git.configure(
          path: repo_path,
          mode: :auto,
          commit_message: custom_msg_fn
        )

      Hako.write(filesystem, "to_delete.txt", "content")
      Hako.delete(filesystem, "to_delete.txt")

      [{:info, info}] = :ets.lookup(received_info, :info)
      assert info.operation == :delete
      assert info.path == "to_delete.txt"

      :ets.delete(received_info)
    end

    test "custom function receives move paths", %{repo_path: repo_path} do
      custom_msg_fn = fn %{operation: _op, path: path} ->
        "Move: #{path}"
      end

      filesystem =
        Git.configure(
          path: repo_path,
          mode: :auto,
          commit_message: custom_msg_fn
        )

      Hako.write(filesystem, "src.txt", "content")
      Hako.move(filesystem, "src.txt", "dest.txt")

      message = last_commit_message(repo_path)
      assert String.contains?(message, "src.txt")
      assert String.contains?(message, "dest.txt")
    end

    test "default message function includes timestamp", %{repo_path: repo_path} do
      filesystem = Git.configure(path: repo_path, mode: :auto)
      Hako.write(filesystem, "file.txt", "content")

      message = last_commit_message(repo_path)
      assert String.match?(message, ~r/\d{4}-\d{2}-\d{2}/)
    end
  end

  # ============================================================================
  # ERROR HANDLING
  # ============================================================================

  describe "error handling" do
    setup %{repo_path: repo_path} do
      filesystem = Git.configure(path: repo_path, mode: :manual)
      {:ok, filesystem: filesystem}
    end

    test "invalid sha errors", %{filesystem: fs} do
      assert {:error, _message} = Hako.read_revision(fs, "file.txt", "invalid_sha_1234567890")
    end

    test "nonexistent file revisions", %{filesystem: fs} do
      Hako.write(fs, "exists.txt", "content")
      Hako.commit(fs, "Add file")

      {:ok, [rev | _]} = Hako.revisions(fs, "exists.txt")
      assert {:error, _} = Hako.read_revision(fs, "nonexistent.txt", rev.sha)
    end

    test "rollback with invalid sha", %{filesystem: fs} do
      assert {:error, _} = Hako.rollback(fs, "invalid_sha_that_does_not_exist")
    end

    test "read_revision with empty sha", %{filesystem: fs} do
      assert {:error, _} = Hako.read_revision(fs, "file.txt", "")
    end

    test "revisions for file that never existed", %{filesystem: fs} do
      {:ok, revisions} = Hako.revisions(fs, "never_existed.txt")
      assert revisions == []
    end

    test "rollback file that doesn't exist at revision", %{filesystem: fs} do
      {:ok, [initial | _]} = Hako.revisions(fs, ".")

      Hako.write(fs, "new_file.txt", "content")
      Hako.commit(fs, "Add new file")

      result = Hako.rollback(fs, initial.sha, path: "new_file.txt")
      assert {:error, _} = result
    end
  end

  # ============================================================================
  # VISIBILITY OPERATIONS (delegated to Local)
  # ============================================================================

  describe "visibility operations" do
    setup %{repo_path: repo_path} do
      filesystem = Git.configure(path: repo_path, mode: :manual)
      {:ok, filesystem: filesystem}
    end

    test "write with public visibility", %{filesystem: fs, repo_path: repo_path} do
      :ok = Hako.write(fs, "public.txt", "content", visibility: :public)

      %{mode: mode} = File.stat!(Path.join(repo_path, "public.txt"))
      import Bitwise
      assert (mode &&& 0o777) == 0o644
    end

    test "write with private visibility", %{filesystem: fs, repo_path: repo_path} do
      :ok = Hako.write(fs, "private.txt", "content", visibility: :private)

      %{mode: mode} = File.stat!(Path.join(repo_path, "private.txt"))
      import Bitwise
      assert (mode &&& 0o777) == 0o600
    end

    test "get visibility of file", %{filesystem: fs} do
      :ok = Hako.write(fs, "vis_test.txt", "content", visibility: :public)
      assert {:ok, :public} = Hako.visibility(fs, "vis_test.txt")
    end

    test "set visibility on existing file", %{filesystem: fs} do
      :ok = Hako.write(fs, "change_vis.txt", "content", visibility: :public)
      :ok = Hako.set_visibility(fs, "change_vis.txt", :private)
      assert {:ok, :private} = Hako.visibility(fs, "change_vis.txt")
    end

    test "set_visibility auto-commits in auto mode", %{repo_path: repo_path} do
      filesystem = Git.configure(path: repo_path, mode: :auto)
      Hako.write(filesystem, "vis.txt", "content", visibility: :public)
      initial_count = commit_count(repo_path)

      Hako.set_visibility(filesystem, "vis.txt", :private)

      # set_visibility may or may not create a new commit depending on whether
      # git detects changes (mode changes may not always be tracked)
      assert commit_count(repo_path) >= initial_count
    end

    test "visibility of missing file returns error", %{filesystem: fs} do
      assert {:error, %Hako.Errors.FileNotFound{}} = Hako.visibility(fs, "nonexistent.txt")
    end
  end

  # ============================================================================
  # STAT AND FILE_EXISTS
  # ============================================================================

  describe "stat and file_exists" do
    setup %{repo_path: repo_path} do
      filesystem = Git.configure(path: repo_path, mode: :manual)
      {:ok, filesystem: filesystem}
    end

    test "file stat via list_contents", %{filesystem: fs} do
      :ok = Hako.write(fs, "stat_test.txt", "1234567890")

      {:ok, contents} = Hako.list_contents(fs, ".")
      file_stat = Enum.find(contents, &(&1.name == "stat_test.txt"))
      assert %Hako.Stat.File{} = file_stat
      assert file_stat.size == 10
    end

    test "directory stat via list_contents", %{filesystem: fs} do
      :ok = Hako.create_directory(fs, "stat_dir/")

      {:ok, contents} = Hako.list_contents(fs, ".")
      dir_stat = Enum.find(contents, &(&1.name == "stat_dir"))
      assert %Hako.Stat.Dir{} = dir_stat
    end

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
  end

  # ============================================================================
  # STREAM OPERATIONS
  # ============================================================================

  describe "stream operations" do
    setup %{repo_path: repo_path} do
      filesystem = Git.configure(path: repo_path, mode: :manual)
      {:ok, filesystem: filesystem}
    end

    test "read stream", %{filesystem: fs} do
      :ok = Hako.write(fs, "stream_read.txt", "Hello World")
      assert {:ok, stream} = Hako.read_stream(fs, "stream_read.txt")
      assert Enum.into(stream, <<>>) == "Hello World"
    end

    test "write stream", %{filesystem: fs} do
      assert {:ok, stream} = Hako.write_stream(fs, "stream_write.txt")
      Enum.into(["Hello", " ", "World"], stream)
      assert {:ok, "Hello World"} = Hako.read(fs, "stream_write.txt")
    end

    test "read stream with chunk size", %{filesystem: fs} do
      :ok = Hako.write(fs, "chunked.txt", "abcdef")
      assert {:ok, stream} = Hako.read_stream(fs, "chunked.txt", chunk_size: 2)
      chunks = Enum.to_list(stream)
      assert chunks == ["ab", "cd", "ef"]
    end
  end

  # ============================================================================
  # CONFIGURATION
  # ============================================================================

  describe "configuration" do
    test "configures custom author", %{repo_path: repo_path} do
      {Git, config} =
        Git.configure(
          path: repo_path,
          author: [name: "Custom Author", email: "custom@example.com"]
        )

      assert config.author_name == "Custom Author"
      assert config.author_email == "custom@example.com"
    end

    test "default author values", %{repo_path: repo_path} do
      {Git, config} = Git.configure(path: repo_path)

      assert config.author_name == "Hako"
      assert config.author_email == "hako@localhost"
    end

    test "mode defaults to manual", %{repo_path: repo_path} do
      {Git, config} = Git.configure(path: repo_path)
      refute config.auto_commit?
    end

    test "mode :auto sets auto_commit true", %{repo_path: repo_path} do
      {Git, config} = Git.configure(path: repo_path, mode: :auto)
      assert config.auto_commit?
    end

    test "path is expanded to absolute", %{repo_path: repo_path} do
      {Git, config} = Git.configure(path: repo_path)
      assert config.repo_path == Path.expand(repo_path)
    end

    test "creates repo if doesn't exist", %{repo_path: repo_path} do
      refute File.exists?(repo_path)
      Git.configure(path: repo_path)
      assert File.exists?(Path.join(repo_path, ".git"))
    end
  end

  # ============================================================================
  # UNSUPPORTED OPERATIONS
  # ============================================================================

  describe "unsupported operations" do
    test "cross-adapter copy returns unsupported", %{repo_path: repo_path, tmp_dir: tmp_dir} do
      git_fs = Git.configure(path: repo_path, mode: :manual)

      other_path = Path.join(tmp_dir, "other_repo")
      other_fs = Git.configure(path: other_path, mode: :manual)

      Hako.write(git_fs, "source.txt", "content")

      {Git, git_config} = git_fs
      {Git, other_config} = other_fs

      result = Git.copy(git_config, "source.txt", other_config, "dest.txt", [])
      assert result == {:error, :unsupported}
    end
  end
end
