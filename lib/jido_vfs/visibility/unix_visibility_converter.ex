defmodule Jido.VFS.Visibility.UnixVisibilityConverter do
  @moduledoc """
  Visibility converter behaviour for unix based systems.
  """
  @type t :: module
  @type permission :: non_neg_integer()
  @type config :: struct

  @callback config(keyword) :: config

  @callback for_file(config, Jido.VFS.Visibility.t()) :: {:ok, permission} | :error
  @callback for_directory(config, Jido.VFS.Visibility.t()) :: {:ok, permission} | :error

  @callback from_file(config, permission) :: Jido.VFS.Visibility.t()
  @callback from_directory(config, permission) :: Jido.VFS.Visibility.t()
end
