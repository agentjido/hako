defmodule Hako.Errors do
  @moduledoc """
  Error handling module for Hako filesystem operations.

  Provides consistent error types and handling across all adapters.
  """

  use Splode,
    error_classes: [
      invalid: Hako.Errors.Invalid,
      not_found: Hako.Errors.NotFound,
      forbidden: Hako.Errors.Forbidden,
      adapter: Hako.Errors.Adapter,
      unknown: Hako.Errors.Unknown
    ],
    unknown_error: Hako.Errors.Unknown.Unknown
end

defmodule Hako.Errors.Invalid do
  @moduledoc "Invalid operation or argument errors"
  use Splode.ErrorClass, class: :invalid
end

defmodule Hako.Errors.NotFound do
  @moduledoc "File or resource not found errors"
  use Splode.ErrorClass, class: :not_found
end

defmodule Hako.Errors.Forbidden do
  @moduledoc "Access denied or permission errors"
  use Splode.ErrorClass, class: :forbidden
end

defmodule Hako.Errors.Adapter do
  @moduledoc "Adapter-specific operation errors"
  use Splode.ErrorClass, class: :adapter
end

defmodule Hako.Errors.Unknown do
  @moduledoc "Unknown or unexpected errors"
  use Splode.ErrorClass, class: :unknown
end

defmodule Hako.Errors.Unknown.Unknown do
  @moduledoc "Fallback unknown error"
  use Splode.Error, fields: [:error], class: :unknown

  def message(%{error: error}) do
    if is_binary(error) do
      to_string(error)
    else
      inspect(error)
    end
  end
end

defmodule Hako.Errors.FileNotFound do
  @moduledoc "File not found error"
  use Splode.Error, fields: [:file_path], class: :not_found

  def message(%{file_path: path}) do
    "File not found: #{path}"
  end
end

defmodule Hako.Errors.DirectoryNotFound do
  @moduledoc "Directory not found error"
  use Splode.Error, fields: [:dir_path], class: :not_found

  def message(%{dir_path: path}) do
    "Directory not found: #{path}"
  end
end

defmodule Hako.Errors.DirectoryNotEmpty do
  @moduledoc "Directory not empty error"
  use Splode.Error, fields: [:dir_path], class: :invalid

  def message(%{dir_path: path}) do
    "Directory not empty: #{path}"
  end
end

defmodule Hako.Errors.InvalidPath do
  @moduledoc "Invalid path error"
  use Splode.Error, fields: [:invalid_path, :reason], class: :invalid

  def message(%{invalid_path: path, reason: reason}) do
    "Invalid path #{path}: #{reason}"
  end
end

defmodule Hako.Errors.PermissionDenied do
  @moduledoc "Permission denied error"
  use Splode.Error, fields: [:target_path, :operation], class: :forbidden

  def message(%{target_path: path, operation: operation}) do
    "Permission denied for #{operation} on #{path}"
  end
end

defmodule Hako.Errors.UnsupportedOperation do
  @moduledoc "Unsupported operation error"
  use Splode.Error, fields: [:operation, :adapter], class: :adapter

  def message(%{operation: operation, adapter: adapter}) do
    "Operation #{operation} not supported by adapter #{adapter}"
  end
end

defmodule Hako.Errors.AdapterError do
  @moduledoc "Generic adapter error"
  use Splode.Error, fields: [:adapter, :reason], class: :adapter

  def message(%{adapter: adapter, reason: reason}) do
    "Adapter #{adapter} error: #{inspect(reason)}"
  end
end

defmodule Hako.Errors.PathTraversal do
  @moduledoc "Path traversal attempt error"
  use Splode.Error, fields: [:attempted_path], class: :invalid

  def message(%{attempted_path: path}) do
    "Path traversal not allowed: #{path}"
  end
end

defmodule Hako.Errors.AbsolutePath do
  @moduledoc "Absolute path not allowed error"
  use Splode.Error, fields: [:absolute_path], class: :invalid

  def message(%{absolute_path: path}) do
    "Absolute paths not allowed: #{path}"
  end
end

defmodule Hako.Errors.NotDirectory do
  @moduledoc "Path is not a directory error"
  use Splode.Error, fields: [:not_dir_path], class: :invalid

  def message(%{not_dir_path: path}) do
    "Path is not a directory: #{path}"
  end
end
