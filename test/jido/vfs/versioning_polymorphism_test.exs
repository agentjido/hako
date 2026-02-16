defmodule Jido.VFS.VersioningPolymorphismTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  describe "polymorphic versioning API" do
    @tag :git
    test "Git adapter works with main Jido.VFS API", %{tmp_dir: tmp_dir} do
      git_dir = Path.join(tmp_dir, "git_repo")
      filesystem = Jido.VFS.Adapter.Git.configure(path: git_dir, mode: :manual)

      # Test polymorphic API
      Jido.VFS.write(filesystem, "test.txt", "initial content")
      assert :ok = Jido.VFS.commit(filesystem, "Initial commit")

      assert {:ok, revisions} = Jido.VFS.revisions(filesystem, "test.txt")
      assert length(revisions) >= 1

      revision = List.first(revisions)
      assert {:ok, "initial content"} = Jido.VFS.read_revision(filesystem, "test.txt", revision.sha)
    end

    test "ETS adapter works with main Jido.VFS API" do
      name = :"test_ets_poly_#{:rand.uniform(10000)}"
      {adapter, config} = Jido.VFS.Adapter.ETS.configure(name: name)
      filesystem = {adapter, config}

      start_supervised!({adapter, config})

      # Create some versioned content first (ETS requires explicit versioning)
      {:ok, _version_id} =
        Jido.VFS.Adapter.ETS.write_version(config, "test.txt", "versioned content", [])

      # Test polymorphic API
      assert :ok = Jido.VFS.commit(filesystem, "ETS commit")

      assert {:ok, revisions} = Jido.VFS.revisions(filesystem, "test.txt")
      assert length(revisions) >= 1

      revision = List.first(revisions)

      assert {:ok, "versioned content"} =
               Jido.VFS.read_revision(filesystem, "test.txt", revision.sha)

      # Test rollback
      assert :ok = Jido.VFS.rollback(filesystem, revision.sha, path: "test.txt")
    end

    test "InMemory adapter works with main Jido.VFS API" do
      name = :"test_memory_poly_#{:rand.uniform(10000)}"
      {adapter, config} = Jido.VFS.Adapter.InMemory.configure(name: name)
      filesystem = {adapter, config}

      start_supervised!({adapter, config})

      # Create some versioned content first (InMemory requires explicit versioning)
      {:ok, _version_id} =
        Jido.VFS.Adapter.InMemory.write_version(config, "test.txt", "versioned content", [])

      # Test polymorphic API
      assert :ok = Jido.VFS.commit(filesystem, "InMemory commit")

      assert {:ok, revisions} = Jido.VFS.revisions(filesystem, "test.txt")
      assert length(revisions) >= 1

      revision = List.first(revisions)

      assert {:ok, "versioned content"} =
               Jido.VFS.read_revision(filesystem, "test.txt", revision.sha)

      # Test rollback
      assert :ok = Jido.VFS.rollback(filesystem, revision.sha, path: "test.txt")
    end

    test "Sprite adapter works with main Jido.VFS API" do
      sprite_name = "test_sprite_poly_#{System.unique_integer([:positive, :monotonic])}"

      filesystem =
        Jido.VFS.Adapter.Sprite.configure(
          client: JidoVfsTest.SpriteFakeClient,
          token: "test-token",
          sprite_name: sprite_name,
          create_on_demand: true,
          root: "/workspace"
        )

      :ok = Jido.VFS.write(filesystem, "test.txt", "initial content")
      assert :ok = Jido.VFS.commit(filesystem, "Initial checkpoint")

      assert {:ok, revisions} = Jido.VFS.revisions(filesystem, "test.txt")
      assert length(revisions) >= 1

      revision = List.first(revisions)
      assert {:ok, "initial content"} = Jido.VFS.read_revision(filesystem, "test.txt", revision.sha)

      :ok = Jido.VFS.write(filesystem, "test.txt", "new content")
      assert :ok = Jido.VFS.rollback(filesystem, revision.sha, path: "test.txt")
      assert {:ok, "initial content"} = Jido.VFS.read(filesystem, "test.txt")
    end

    test "unsupported adapters return proper errors" do
      {adapter, config} = Jido.VFS.Adapter.Local.configure(prefix: System.tmp_dir!())
      filesystem = {adapter, config}

      assert {:error, %Jido.VFS.Errors.UnsupportedOperation{operation: :commit}} =
               Jido.VFS.commit(filesystem, "test")

      assert {:error, %Jido.VFS.Errors.UnsupportedOperation{operation: :revisions}} =
               Jido.VFS.revisions(filesystem, "test.txt")

      assert {:error, %Jido.VFS.Errors.UnsupportedOperation{operation: :read_revision}} =
               Jido.VFS.read_revision(filesystem, "test.txt", "rev")

      assert {:error, %Jido.VFS.Errors.UnsupportedOperation{operation: :rollback}} =
               Jido.VFS.rollback(filesystem, "rev")
    end

    @tag :git
    test "all versioning adapters return consistent format" do
      # Git format (maintains backward compatibility)
      git_dir = System.tmp_dir!() |> Path.join("git_#{:rand.uniform(10000)}")
      git_fs = Jido.VFS.Adapter.Git.configure(path: git_dir, mode: :manual)

      Jido.VFS.write(git_fs, "test.txt", "git content")
      Jido.VFS.commit(git_fs, "Git commit")

      {:ok, git_revisions} = Jido.VFS.revisions(git_fs, "test.txt")
      git_revision = List.first(git_revisions)

      # Git should return Jido.VFS.Revision struct
      assert %Jido.VFS.Revision{} = git_revision
      assert is_binary(git_revision.sha)

      # ETS format (new standardized format)
      ets_name = :"test_ets_format_#{:rand.uniform(10000)}"
      {ets_adapter, ets_config} = Jido.VFS.Adapter.ETS.configure(name: ets_name)
      ets_fs = {ets_adapter, ets_config}
      start_supervised!({ets_adapter, ets_config})

      {:ok, _} = Jido.VFS.Adapter.ETS.write_version(ets_config, "test.txt", "ets content", [])

      {:ok, ets_revisions} = Jido.VFS.revisions(ets_fs, "test.txt")
      ets_revision = List.first(ets_revisions)

      # ETS should return standardized revision struct format
      assert %Jido.VFS.Revision{} = ets_revision
      assert is_binary(ets_revision.sha)
      assert ets_revision.author_name == "ETS Adapter"

      # Sprite format (new standardized format)
      sprite_name = "test_sprite_format_#{System.unique_integer([:positive, :monotonic])}"

      sprite_fs =
        Jido.VFS.Adapter.Sprite.configure(
          client: JidoVfsTest.SpriteFakeClient,
          token: "test-token",
          sprite_name: sprite_name,
          create_on_demand: true,
          root: "/workspace"
        )

      :ok = Jido.VFS.write(sprite_fs, "test.txt", "sprite content")
      :ok = Jido.VFS.commit(sprite_fs, "Sprite commit")

      {:ok, sprite_revisions} = Jido.VFS.revisions(sprite_fs, "test.txt")
      sprite_revision = List.first(sprite_revisions)

      assert %Jido.VFS.Revision{} = sprite_revision
      assert is_binary(sprite_revision.sha)
      assert sprite_revision.author_name == "Sprite Checkpoint"

      File.rm_rf!(git_dir)
    end
  end
end
