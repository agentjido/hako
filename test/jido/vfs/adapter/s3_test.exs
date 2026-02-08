defmodule Jido.VFS.Adapter.S3Test do
  use ExUnit.Case
  import Jido.VFS.AdapterTest

  @moduletag :s3

  setup do
    config = HakoTest.Minio.config()
    HakoTest.Minio.clean_bucket("default")
    HakoTest.Minio.recreate_bucket("default")

    on_exit(fn ->
      HakoTest.Minio.clean_bucket("default")
    end)

    {:ok, config: config, bucket: "default"}
  end

  adapter_test %{config: config} do
    filesystem = Jido.VFS.Adapter.S3.configure(config: config, bucket: "default")
    {:ok, filesystem: filesystem}
  end

  describe "cross bucket" do
    setup %{config: config} do
      config_b = HakoTest.Minio.config()
      HakoTest.Minio.clean_bucket("secondary")
      HakoTest.Minio.recreate_bucket("secondary")

      on_exit(fn ->
        HakoTest.Minio.clean_bucket("secondary")
      end)

      {:ok, config_a: config, config_b: config_b}
    end

    test "copy", %{config_a: config_a, config_b: config_b} do
      filesystem_a = Jido.VFS.Adapter.S3.configure(config: config_a, bucket: "default")
      filesystem_b = Jido.VFS.Adapter.S3.configure(config: config_b, bucket: "secondary")

      :ok = Jido.VFS.write(filesystem_a, "test.txt", "Hello World")

      assert :ok =
               Jido.VFS.copy_between_filesystem(
                 {filesystem_a, "test.txt"},
                 {filesystem_b, "other.txt"}
               )

      assert {:ok, "Hello World"} = Jido.VFS.read(filesystem_b, "other.txt")
    end
  end
end
