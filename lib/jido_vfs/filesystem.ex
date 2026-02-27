defmodule Jido.VFS.Filesystem do
  @moduledoc """
  Behaviour of a `Jido.VFS` filesystem.
  """
  @callback write(path :: Path.t(), contents :: binary, opts :: keyword()) :: :ok | {:error, term}
  @callback read(path :: Path.t(), opts :: keyword()) :: {:ok, binary} | {:error, term}
  @callback read_stream(path :: Path.t(), opts :: keyword()) ::
              {:ok, Enumerable.t()} | {:error, term}
  @callback delete(path :: Path.t(), opts :: keyword()) :: :ok | {:error, term}
  @callback move(source :: Path.t(), destination :: Path.t(), opts :: keyword()) ::
              :ok | {:error, term}
  @callback copy(source :: Path.t(), destination :: Path.t(), opts :: keyword()) ::
              :ok | {:error, term}
  @callback file_exists(path :: Path.t(), opts :: keyword()) ::
              {:ok, :exists | :missing} | {:error, term}
  @callback list_contents(path :: Path.t(), opts :: keyword()) ::
              {:ok, [%Jido.VFS.Stat.Dir{} | %Jido.VFS.Stat.File{}]} | {:error, term}

  @doc false
  @spec __using__(Macro.t()) :: Macro.t()
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Jido.VFS.Filesystem
      {adapter, opts} = Jido.VFS.Filesystem.parse_opts(__MODULE__, opts)
      @adapter adapter
      @opts opts
      @key {Jido.VFS.Filesystem, __MODULE__}

      def init do
        opts = Jido.VFS.Filesystem.merge_app_env(@opts, __MODULE__)
        filesystem = Jido.VFS.configure!(@adapter, opts)

        :persistent_term.put(@key, filesystem)

        filesystem
      end

      def __filesystem__ do
        case :persistent_term.get(@key, :__jido_vfs_missing__) do
          :__jido_vfs_missing__ -> init()
          filesystem -> filesystem
        end
      end

      if @adapter.starts_processes() do
        def child_spec(init_arg) do
          __filesystem__()
          |> Supervisor.child_spec(init_arg)
        end
      end

      @impl true
      def write(path, contents, opts \\ []),
        do: Jido.VFS.write(__filesystem__(), path, contents, opts)

      @impl true
      def read(path, opts \\ []),
        do: Jido.VFS.read(__filesystem__(), path, opts)

      @impl true
      def read_stream(path, opts \\ []),
        do: Jido.VFS.read_stream(__filesystem__(), path, opts)

      @impl true
      def delete(path, opts \\ []),
        do: Jido.VFS.delete(__filesystem__(), path, opts)

      @impl true
      def move(source, destination, opts \\ []),
        do: Jido.VFS.move(__filesystem__(), source, destination, opts)

      @impl true
      def copy(source, destination, opts \\ []),
        do: Jido.VFS.copy(__filesystem__(), source, destination, opts)

      @impl true
      def file_exists(path, opts \\ []),
        do: Jido.VFS.file_exists(__filesystem__(), path, opts)

      @impl true
      def list_contents(path, opts \\ []),
        do: Jido.VFS.list_contents(__filesystem__(), path, opts)
    end
  end

  def parse_opts(module, opts) do
    opts
    |> merge_app_env(module)
    |> Keyword.put_new(:name, module)
    |> Keyword.pop!(:adapter)
  end

  def merge_app_env(opts, module) do
    case Keyword.fetch(opts, :otp_app) do
      {:ok, otp_app} ->
        config = Application.get_env(otp_app, module, [])
        Keyword.merge(opts, config)

      :error ->
        opts
    end
  end
end
