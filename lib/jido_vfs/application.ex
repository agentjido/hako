defmodule Jido.VFS.Application do
  @moduledoc """
  OTP application entry point for Jido.VFS support processes.
  """

  use Application

  @doc """
  Starts the supervision tree used by Jido.VFS.
  """
  @spec start(Application.start_type(), term()) :: Supervisor.on_start()
  def start(_type, _args) do
    children = [
      Jido.VFS.Registry
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
