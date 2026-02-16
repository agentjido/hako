defmodule Jido.VFS.Adapter.Sprite.Versioning do
  @moduledoc """
  Versioning wrapper for Sprite adapter.

  Sprite checkpoints are VM-wide snapshots. This wrapper maps checkpoint
  operations into the polymorphic `Jido.VFS.Adapter.Versioning` interface.
  """

  @behaviour Jido.VFS.Adapter.Versioning

  alias Jido.VFS.Adapter.Sprite
  alias Jido.VFS.Revision

  @impl Jido.VFS.Adapter.Versioning
  def commit(config, message \\ nil, _opts \\ []) do
    comment = message || "checkpoint #{DateTime.utc_now() |> DateTime.to_iso8601()}"

    case Sprite.create_checkpoint(config, comment: comment) do
      {:ok, _version_id} -> :ok
      error -> error
    end
  end

  @impl Jido.VFS.Adapter.Versioning
  def revisions(config, path \\ ".", opts \\ []) do
    case Sprite.list_versions(config, path) do
      {:ok, versions} ->
        limit = Keyword.get(opts, :limit)
        since = Keyword.get(opts, :since)
        until = Keyword.get(opts, :until)

        revisions =
          versions
          |> filter_by_time_range(since, until)
          |> apply_limit(limit)
          |> Enum.map(&to_revision/1)

        {:ok, revisions}

      error ->
        error
    end
  end

  @impl Jido.VFS.Adapter.Versioning
  def read_revision(config, path, revision, _opts \\ []) do
    Sprite.read_version(config, path, revision)
  end

  @impl Jido.VFS.Adapter.Versioning
  def rollback(config, revision, opts \\ []) do
    path = Keyword.get(opts, :path)

    if is_binary(path) and path != "" do
      with {:ok, content} <- Sprite.read_version(config, path, revision),
           :ok <- Sprite.write(config, path, content, []) do
        :ok
      end
    else
      Sprite.restore_version(config, ".", revision)
    end
  end

  defp filter_by_time_range(versions, since, until) do
    versions
    |> filter_since(since)
    |> filter_until(until)
  end

  defp filter_since(versions, nil), do: versions

  defp filter_since(versions, since) do
    since_timestamp = DateTime.to_unix(since)
    Enum.filter(versions, fn version -> version.timestamp >= since_timestamp end)
  end

  defp filter_until(versions, nil), do: versions

  defp filter_until(versions, until) do
    until_timestamp = DateTime.to_unix(until)
    Enum.filter(versions, fn version -> version.timestamp <= until_timestamp end)
  end

  defp apply_limit(versions, nil), do: versions
  defp apply_limit(versions, limit), do: Enum.take(versions, limit)

  defp to_revision(%{version_id: version_id, timestamp: timestamp}) do
    datetime =
      case DateTime.from_unix(timestamp) do
        {:ok, dt} -> dt
        {:error, _} -> DateTime.utc_now()
      end

    %Revision{
      sha: version_id,
      author_name: "Sprite Checkpoint",
      author_email: "sprites@jido.vfs.local",
      message: "Sprite checkpoint #{version_id}",
      timestamp: datetime
    }
  end
end
