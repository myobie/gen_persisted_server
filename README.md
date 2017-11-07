# GenPersistedServer

Persist `state` after updates.

## Installation

```elixir
def deps do
  [
    {:gen_persisted_server, "~> 0.1.0"}
  ]
end
```

## Usage

```ex
defmodule FileAdapter do
  @behaviour GenPersistedServer.StorageAdapter
  @dir "../path/to/somewhere"

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
end

defmodule Game do
  use GenPersistedServer, adapter: FileAdapter

  def init(_) do
    {:ok, %{moves: [], over: false}}
  end

  def handle_call({:move, pos}, _from, %{moves: moves} = state) do
    {:reply, pos, %{state | moves: [move | moves]}}
  end

  def handle_info(:player_timeout, state) do
    {:stop, :timeout, %{state | over: true}}
  end
end

{:ok, pid} = GenPersistedServer.start_link(Game, persisted_id: "1")
```

Also take a look at the tests.
