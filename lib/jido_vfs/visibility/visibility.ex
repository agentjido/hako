defmodule Jido.VFS.Visibility do
  @moduledoc """
  Helpers for working with portable and adapter-specific visibility values.
  """

  @type t :: portable | custom
  @type portable :: :public | :private
  @type custom :: term

  @doc """
  Returns `true` when the visibility is one of the portable values.
  """
  @spec portable?(any) :: boolean
  def portable?(:public), do: true
  def portable?(:private), do: true
  def portable?(_), do: false

  @doc """
  Guards a visibility value, returning the portable visibility or `:error`.
  """
  @spec guard_portable(any) :: {:ok, Jido.VFS.Visibility.portable()} | :error
  def guard_portable(visibility) do
    if portable?(visibility) do
      {:ok, visibility}
    else
      :error
    end
  end
end
