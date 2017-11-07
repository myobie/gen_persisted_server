defmodule GenPersistedServer.StorageAdapter do
  @callback get(id :: term) :: {:ok, map} | {:error, term}
  @callback put(id :: term, state :: map) :: :ok | {:error, term}
end
