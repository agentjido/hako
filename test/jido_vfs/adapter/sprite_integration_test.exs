defmodule Jido.VFS.Adapter.SpriteIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :sprites

  @sprites_module :"Elixir.Sprites"
  @sprites_loaded Code.ensure_loaded?(@sprites_module)
  @sprites_token System.get_env("SPRITES_TOKEN")

  if not @sprites_loaded do
    @moduletag skip: "sprites-ex dependency not available"
  end

  if @sprites_loaded and (is_nil(@sprites_token) or @sprites_token == "") do
    @moduletag skip: "SPRITES_TOKEN not set"
  end

  setup_all do
    sprite_name = "jido-vfs-test-#{System.unique_integer([:positive, :monotonic])}"

    filesystem =
      Jido.VFS.Adapter.Sprite.configure(
        token: @sprites_token,
        sprite_name: sprite_name,
        create_on_demand: true,
        root: "/jido_vfs"
      )

    on_exit(fn ->
      {_adapter, config} = filesystem

      if function_exported?(config.client, :destroy, 1) do
        _ = config.client.destroy(config.sprite)
      end
    end)

    {:ok, filesystem: filesystem}
  end

  test "write/read roundtrip for text", %{filesystem: filesystem} do
    assert :ok = Jido.VFS.write(filesystem, "hello.txt", "sprite adapter")
    assert {:ok, "sprite adapter"} = Jido.VFS.read(filesystem, "hello.txt")
  end

  test "write/read roundtrip for binary", %{filesystem: filesystem} do
    payload = <<0, 10, 255, 100, 0, 55>>

    assert :ok = Jido.VFS.write(filesystem, "binary.bin", payload)
    assert {:ok, ^payload} = Jido.VFS.read(filesystem, "binary.bin")
  end

  test "stat and list_contents return metadata", %{filesystem: filesystem} do
    assert :ok = Jido.VFS.write(filesystem, "meta/file.txt", "abc")
    assert {:ok, %Jido.VFS.Stat.File{} = stat} = Jido.VFS.stat(filesystem, "meta/file.txt")
    assert stat.size == 3

    assert {:ok, entries} = Jido.VFS.list_contents(filesystem, "meta")
    assert Enum.any?(entries, &match?(%Jido.VFS.Stat.File{name: "file.txt"}, &1))
  end

  test "checkpoint versioning works through polymorphic API", %{filesystem: filesystem} do
    assert :ok = Jido.VFS.write(filesystem, "versioned.txt", "v1")
    assert :ok = Jido.VFS.commit(filesystem, "v1 checkpoint")

    assert :ok = Jido.VFS.write(filesystem, "versioned.txt", "v2")
    assert :ok = Jido.VFS.commit(filesystem, "v2 checkpoint")

    assert {:ok, revisions} = Jido.VFS.revisions(filesystem, "versioned.txt")
    assert length(revisions) >= 2

    old_revision = List.last(revisions)
    assert {:ok, "v1"} = Jido.VFS.read_revision(filesystem, "versioned.txt", old_revision.sha)

    assert :ok = Jido.VFS.rollback(filesystem, old_revision.sha, path: "versioned.txt")
    assert {:ok, "v1"} = Jido.VFS.read(filesystem, "versioned.txt")
  end
end
