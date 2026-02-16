defmodule Jido.VFS.Adapter.SpriteTest do
  use ExUnit.Case, async: true

  import Jido.VFS.AdapterTest

  alias Jido.VFS.Adapter.Sprite
  alias JidoVfsTest.SpriteFakeClient

  adapter_test do
    sprite_name = "sprite_adapter_contract_#{System.unique_integer([:positive, :monotonic])}"

    filesystem =
      Sprite.configure(
        client: SpriteFakeClient,
        token: "test-token",
        sprite_name: sprite_name,
        create_on_demand: true,
        root: "/workspace"
      )

    on_exit(fn -> cleanup(filesystem) end)

    {:ok, filesystem: filesystem}
  end

  describe "binary-safe mode" do
    test "write/read supports binary payloads with null bytes" do
      filesystem = new_filesystem("sprite_binary")
      on_exit(fn -> cleanup(filesystem) end)

      payload = <<0, 1, 2, 255, 0, 12, 42, 120>>

      assert :ok = Jido.VFS.write(filesystem, "bin/data.bin", payload)
      assert {:ok, ^payload} = Jido.VFS.read(filesystem, "bin/data.bin")
    end

    test "append concatenates binary content" do
      filesystem = new_filesystem("sprite_append")
      on_exit(fn -> cleanup(filesystem) end)

      :ok = Jido.VFS.write(filesystem, "append.bin", <<1, 2, 3>>)
      {_, config} = filesystem

      assert :ok = Sprite.append(config, "append.bin", <<4, 5>>, [])
      assert {:ok, <<1, 2, 3, 4, 5>>} = Jido.VFS.read(filesystem, "append.bin")
    end
  end

  describe "raw mode" do
    test "read/write works for plain text content" do
      filesystem = new_filesystem("sprite_raw", encoding: :raw)
      on_exit(fn -> cleanup(filesystem) end)

      assert :ok = Jido.VFS.write(filesystem, "notes.txt", "hello from raw mode")
      assert {:ok, "hello from raw mode"} = Jido.VFS.read(filesystem, "notes.txt")
    end
  end

  describe "metadata and cross-config copy" do
    test "stat/2 returns file metadata" do
      filesystem = new_filesystem("sprite_stat")
      on_exit(fn -> cleanup(filesystem) end)

      :ok = Jido.VFS.write(filesystem, "stats/file.txt", "abc123")
      {_, config} = filesystem

      assert {:ok, %Jido.VFS.Stat.File{} = stat} = Sprite.stat(config, "stats/file.txt")
      assert stat.name == "file.txt"
      assert stat.size == 6
      assert is_integer(stat.mtime)
      assert stat.visibility in [:public, :private]
    end

    test "copy_between_filesystem works across different roots on same sprite" do
      sprite_name = "sprite_cross_copy_#{System.unique_integer([:positive, :monotonic])}"

      fs_a =
        Sprite.configure(
          client: SpriteFakeClient,
          token: "test-token",
          sprite_name: sprite_name,
          create_on_demand: true,
          root: "/root-a"
        )

      fs_b =
        Sprite.configure(
          client: SpriteFakeClient,
          token: "test-token",
          sprite_name: sprite_name,
          create_on_demand: false,
          root: "/root-b"
        )

      on_exit(fn ->
        cleanup(fs_a)
        cleanup(fs_b)
      end)

      :ok = Jido.VFS.write(fs_a, "file.txt", "shared")

      assert :ok =
               Jido.VFS.copy_between_filesystem(
                 {fs_a, "file.txt"},
                 {fs_b, "copied.txt"}
               )

      assert {:ok, "shared"} = Jido.VFS.read(fs_b, "copied.txt")
    end
  end

  describe "checkpoint-backed versioning" do
    test "write_version/list_versions/get_latest_version/read_version/restore_version/delete_version" do
      filesystem = new_filesystem("sprite_versions")
      on_exit(fn -> cleanup(filesystem) end)
      {_, config} = filesystem

      assert {:ok, version_1} = Sprite.write_version(config, "versioned.txt", "one", [])
      assert {:ok, version_2} = Sprite.write_version(config, "versioned.txt", "two", [])
      assert version_1 != version_2

      assert {:ok, versions} = Sprite.list_versions(config, "versioned.txt")
      assert Enum.any?(versions, &(&1.version_id == version_1))
      assert Enum.any?(versions, &(&1.version_id == version_2))

      assert {:ok, latest} = Sprite.get_latest_version(config, "versioned.txt")
      assert latest == version_2

      assert {:ok, "one"} = Sprite.read_version(config, "versioned.txt", version_1)
      assert {:ok, "two"} = Jido.VFS.read(filesystem, "versioned.txt")

      assert :ok = Sprite.restore_version(config, "versioned.txt", version_1)
      assert {:ok, "one"} = Jido.VFS.read(filesystem, "versioned.txt")

      assert :ok = Sprite.delete_version(config, "versioned.txt", version_1)
      assert {:ok, remaining_versions} = Sprite.list_versions(config, "versioned.txt")
      refute Enum.any?(remaining_versions, &(&1.version_id == version_1))
    end
  end

  defp new_filesystem(prefix, opts \\ []) do
    sprite_name = "#{prefix}_#{System.unique_integer([:positive, :monotonic])}"

    Sprite.configure(
      [
        client: SpriteFakeClient,
        token: "test-token",
        sprite_name: sprite_name,
        create_on_demand: true,
        root: "/workspace"
      ] ++ opts
    )
  end

  defp cleanup({_adapter, %Sprite.Config{client: client, sprite: sprite}})
       when is_atom(client) and not is_nil(sprite) do
    if function_exported?(client, :destroy, 1) do
      _ = client.destroy(sprite)
    end

    :ok
  end

  defp cleanup(_), do: :ok
end
