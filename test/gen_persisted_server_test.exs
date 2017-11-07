defmodule GenPersistedServerTest do
  use ExUnit.Case
  doctest GenPersistedServer

  defmodule Adapter do
    @behaviour GenPersistedServer.StorageAdapter
    @dir System.tmp_dir()

    def get(id) do
      with path = Path.join(@dir, "#{id}.json"),
           {:ok, data} <- File.read(path)
      do
        Poison.decode(data)
      else
        {:error, :enoent} -> {:ok, %{}}
      end
    end

    def put(id, state) do
      with path = Path.join(@dir, "#{id}.json"),
           {:ok, data} <- Poison.encode(state),
        do: File.write(path, data)
    end

    def clear(id) do
      path = Path.join(@dir, "#{id}.json")
      File.rm(path)
    end
  end

  defmodule TestPS do
    use GenPersistedServer, adapter: Adapter

    def init(state) when state == %{}, do: {:ok, %{"calls" => 0}}
    def init(state), do: {:ok, state}

    defp increment(state),
      do: Map.update(state, "calls", 0, fn count -> count + 1 end)

    def handle_call(:hello, _from, state) do
      {:reply, :goodbye, increment(state)}
    end

    def handle_call(:count, _from, state) do
      {:reply, Map.get(state, "calls"), state}
    end
  end

  setup do
    Adapter.clear("1")
    Adapter.clear("2")
    :ok
  end

  test "creates a GenServer" do
    {:ok, pid} = GenPersistedServer.start_link(TestPS, %{persisted_id: "1"})
    assert Process.alive?(pid), "pid is not alive"
    assert GenPersistedServer.call(pid, :count) == 0
    assert GenPersistedServer.call(pid, :hello) == :goodbye
    assert GenPersistedServer.call(pid, :count) == 1
    GenPersistedServer.stop(pid)
  end

  test "recovers state from adapter" do
    {:ok, pid} = GenPersistedServer.start_link(TestPS, %{persisted_id: "1"})
    assert GenPersistedServer.call(pid, :hello) == :goodbye
    assert GenPersistedServer.call(pid, :count) == 1
    GenPersistedServer.stop(pid)

    {:ok, pid} = GenPersistedServer.start_link(TestPS, %{persisted_id: "1"})
    # remember the count was 1
    assert GenPersistedServer.call(pid, :count) == 1
  end
end
