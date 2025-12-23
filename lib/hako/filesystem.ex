defmodule Hako.Filesystem do
  @moduledoc """
  Behaviour of a `Hako` filesystem.
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
              {:ok, [%Hako.Stat.Dir{} | %Hako.Stat.File{}]} | {:error, term}

  @doc false
  @spec __using__(Macro.t()) :: Macro.t()
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Hako.Filesystem
      {adapter, opts} = Hako.Filesystem.parse_opts(__MODULE__, opts)
      @adapter adapter
      @opts opts
      @key {Hako.Filesystem, __MODULE__}

      def init do
        filesystem =
          @opts
          |> Hako.Filesystem.merge_app_env(__MODULE__)
          |> @adapter.configure()

        :persistent_term.put(@key, filesystem)

        filesystem
      end

      def __filesystem__ do
        :persistent_term.get(@key, init())
      end

      if @adapter.starts_processes() do
        def child_spec(init_arg) do
          __filesystem__()
          |> Supervisor.child_spec(init_arg)
        end
      end

      @impl true
      def write(path, contents, opts \\ []),
        do: Hako.write(__filesystem__(), path, contents, opts)

      @impl true
      def read(path, opts \\ []),
        do: Hako.read(__filesystem__(), path, opts)

      @impl true
      def read_stream(path, opts \\ []),
        do: Hako.read_stream(__filesystem__(), path, opts)

      @impl true
      def delete(path, opts \\ []),
        do: Hako.delete(__filesystem__(), path, opts)

      @impl true
      def move(source, destination, opts \\ []),
        do: Hako.move(__filesystem__(), source, destination, opts)

      @impl true
      def copy(source, destination, opts \\ []),
        do: Hako.copy(__filesystem__(), source, destination, opts)

      @impl true
      def file_exists(path, opts \\ []),
        do: Hako.file_exists(__filesystem__(), path, opts)

      @impl true
      def list_contents(path, opts \\ []),
        do: Hako.list_contents(__filesystem__(), path, opts)
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
