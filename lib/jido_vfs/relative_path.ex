defmodule Jido.VFS.RelativePath do
  @moduledoc """
  Utilities for validating and normalizing relative filesystem paths.
  """

  @type t :: Path.t()

  @slash [?/, ?\\]

  @doc """
  Normalizes a relative path and rejects absolute or traversal paths.
  """
  @spec normalize(binary) :: {:ok, t} | {:error, term}
  def normalize(path) do
    case relative?(path) do
      true ->
        case expand(path) do
          {:ok, expanded} ->
            if String.ends_with?(path, "/") do
              {:ok, String.trim_trailing(expanded, "/") <> "/"}
            else
              {:ok, expanded}
            end

          {:error, :traversal} ->
            {:error, {:path, :traversal}}
        end

      false ->
        {:error, {:path, :absolute}}
    end
  end

  @doc """
  Returns `true` when the given path is relative for Unix and Windows path formats.
  """
  @spec relative?(binary) :: boolean
  def relative?(<<c1, c2, _::binary>>) when c1 in @slash and c2 in @slash,
    do: false

  def relative?(<<_letter, ?:, slash, _::binary>>) when slash in @slash,
    do: false

  def relative?(<<_letter, ?:, _::binary>>), do: false
  def relative?(<<slash, _::binary>>) when slash in @slash, do: false
  def relative?(path) when is_binary(path), do: true

  @doc """
  Expands `.` path segments and rejects parent traversal beyond the root.
  """
  @spec expand(t) :: {:ok, t} | {:error, term}
  def expand(<<"../", _::binary>>), do: {:error, :traversal}

  def expand(path) do
    try do
      expanded =
        path
        |> Path.relative_to("/")
        |> expand_dot()

      {:ok, expanded}
    catch
      :traversal -> {:error, :traversal}
    end
  end

  defp expand_dot(<<letter, ":/", rest::binary>>) when letter in ?A..?Z, do: expand_dot(rest)
  defp expand_dot(path), do: expand_dot(:binary.split(path, "/", [:global]), [])
  defp expand_dot([".." | t], [_, _ | acc]), do: expand_dot(t, acc)
  defp expand_dot([".." | _t], []), do: throw(:traversal)
  defp expand_dot(["." | t], acc), do: expand_dot(t, acc)
  defp expand_dot([h | t], acc), do: expand_dot(t, ["/", h | acc])
  defp expand_dot([], []), do: ""
  defp expand_dot([], ["/" | acc]), do: IO.iodata_to_binary(:lists.reverse(acc))

  @doc """
  Joins a storage prefix with a normalized relative path, preserving a trailing slash.
  """
  @spec join_prefix(Path.t(), t) :: Path.t()
  def join_prefix(prefix, path) do
    join = Path.join(prefix, path)

    case String.last(path) do
      "/" -> join <> "/"
      _ -> join
    end
  end

  @doc """
  Removes a prefix from a fully-qualified storage path.
  """
  @spec strip_prefix(Path.t(), t) :: Path.t()
  def strip_prefix(prefix, path) do
    Path.relative_to(path, prefix)
  end

  @doc """
  Ensures the given path represents a directory path ending in `/`.
  """
  @spec assert_directory(Path.t()) :: {:ok, Path.t()} | {:error, :enotdir}
  def assert_directory(path) do
    if String.ends_with?(path, "/") do
      {:ok, path}
    else
      {:error, :enotdir}
    end
  end
end
