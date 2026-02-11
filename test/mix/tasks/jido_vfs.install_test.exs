defmodule Mix.Tasks.JidoVfs.InstallTest do
  use ExUnit.Case, async: true
  import Igniter.Test

  test "it warns when run" do
    # generate a test project
    test_project()
    # run our task
    |> Igniter.compose_task("jido_vfs.install", [])
    # see tools in `Igniter.Test` for available assertions & helpers
    |> assert_has_notice("""
    Jido VFS has been installed !

    Checkout the quickstart guide:
    https://github.com/agentjido/jido_vfs?tab=readme-ov-file#quick-start

    """)
  end
end
