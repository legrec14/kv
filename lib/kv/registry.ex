defmodule KV.Registry do
  alias Hex.API.Key
  use GenServer

  # -------------------------------------------------------------------------- #
  #                            Client API (process)                            #
  # -------------------------------------------------------------------------- #

  @doc """
  Starts the registry with the given options.

  ':name' is always required.
  """
  def start_link(opts) do
    # 1. Pass the name to GenServer's init
    server = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, server, opts)
  end

  @doc """
  Looks up the bucket pid for 'name' stored in 'server'.

  Returns '{:ok, pid}' if the bucket exists, 'error' otherwise.
  """
  def lookup(server, name) do
    # 2. Lookup is now done directly in ETS, without accessing the server
    case :ets.lookup(server, name) do
      [{^name, pid}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc """
  Ensures there is a bucket associated with the given 'name' in 'server'.
  """
  def create(server, name) do
    GenServer.cast(server, {:create, name})
  end

  # -------------------------------------------------------------------------- #
  #                   GeneServer Callbacks: Server (process)                   #
  # -------------------------------------------------------------------------- #

  @impl true
  def init(table) do
    # 3. We have replaced the names map by the ETS table
    names = :ets.new(table, [:named_table, :set, :protected, read_concurrency: true])
    refs = %{}
    {:ok, {names, refs}}
  end

  # 4. The previous handle_call callback for lookup was removed.

  @impl true
  def handle_cast({:create, name}, {names, refs}) do
    # Read and write to the ETS table instead of the map
    case lookup(names, name) do
      {:ok, _pid} ->
        {:noreply, {names, refs}}

      :error ->
        {:ok, pid} = DynamicSupervisor.start_child(KV.BucketSupervisor, KV.Bucket)
        ref = Process.monitor(pid)
        refs = Map.put(refs, ref, name)
        :ets.insert(names, {name, pid})
        {:noreply, {names, refs}}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, {names, refs}) do
    # 6. Delete from the ETS table instead of the map
    {name, refs} = Map.pop(refs, ref)
    :ets.delete(names, name)
    {:noreply, {names, refs}}
  end

  @impl true
  def handle_info(msg, state) do
    require Logger
    Logger.debug("Unexpected message in KV.Registry: #{inspect(msg)}")
    {:noreply, state}
  end
end
