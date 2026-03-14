defmodule Jido.VFS.Stat.Dir do
  @moduledoc """
  Metadata for a directory entry returned by adapter listing and stat operations.
  """

  @type t :: %__MODULE__{
          name: String.t() | nil,
          size: non_neg_integer() | nil,
          mtime: DateTime.t() | nil,
          visibility: Jido.VFS.Visibility.t() | nil
        }

  defstruct name: nil, size: nil, mtime: nil, visibility: nil
end
