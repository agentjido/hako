defmodule Jido.VFS.Registry do
  @moduledoc """
  Elixir registry to register adapter instances on for adapters, which need processes.

  ## Registration

  Register instances with the via tuple of: `Jido.VFS.Registry.via(adapter, name)`

  """

  @doc false
  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_) do
    Registry.child_spec(keys: :unique, name: __MODULE__)
  end

  @doc false
  @spec via(module(), term()) :: {:via, Registry, {module(), {module(), term()}}}
  def via(adapter, name) do
    {:via, Registry, {__MODULE__, {adapter, name}}}
  end
end
