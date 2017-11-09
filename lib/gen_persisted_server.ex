defmodule GenPersistedServer do
  @moduledoc """
  Documentation for GenPersistedServer.
  """

  ### Copied all the callbacks from GenServer ###

  @callback init(args :: term) ::
      {:ok, state} |
      {:ok, state, timeout | :hibernate} |
      :ignore |
      {:stop, reason :: any} when state: any

  @callback handle_call(request :: term, from, state :: term) ::
    {:reply, reply, new_state} |
    {:reply, reply, new_state, timeout | :hibernate} |
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason, reply, new_state} |
    {:stop, reason, new_state} when reply: term, new_state: term, reason: term

  @callback handle_cast(request :: term, state :: term) ::
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason :: term, new_state} when new_state: term

  @callback handle_info(msg :: :timeout | term, state :: term) ::
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason :: term, new_state} when new_state: term

  @callback terminate(reason, state :: term) ::
    term when reason: :normal | :shutdown | {:shutdown, term} | term

  @callback code_change(old_vsn, state :: term, extra :: term) ::
    {:ok, new_state :: term} |
    {:error, reason :: term} when old_vsn: term | {:down, term}

  @callback format_status(reason, pdict_and_state :: list) ::
    term when reason: :normal | :terminate

  @optional_callbacks format_status: 2

  @type from :: {pid, tag :: term}

  defp append_server(module) do
    Module.concat(module, :Server)
  end

  def start_link(module, args, options \\ []),
    do: GenServer.start_link(append_server(module), args, options)

  def stop(server),
    do: GenServer.stop(server)

  def cast(server, request),
    do: GenServer.cast(server, request)

  def call(server, request),
    do: GenServer.call(server, request)

  def call(server, request, timeout),
    do: GenServer.call(server, request, timeout)

  defmacro __using__(opts) do
    adapter = Keyword.get(opts, :adapter, Application.get_env(:gen_persisted_server, :adapter))
    opts = Keyword.delete(opts, :adapter)
    original = quote do __MODULE__ end

    if is_nil(adapter),
      do: raise "Must provide a storage adapter in your mix config or as an option when using GenPersistedServer"

    quote location: :keep, bind_quoted: [adapter: adapter, opts: opts, original: original] do
      @behaviour GenPersistedServer

      defmodule Server do
        @adapter adapter
        @original original
        use GenServer, opts

        defp get_state(id) do
          apply(@adapter, :get, [id])
        end

        defp put_state(id, new_state) do
          new_state = apply(@original, :sanitize_state, [new_state])
          apply(@adapter, :put, [id, new_state])
        end

        def init(args) do
          persisted_id = Map.get(args, :persisted_id)
          args = Map.delete(args, :persisted_id)

          if is_nil(persisted_id),
            do: raise "Must provide a persisted_id to init/1 when using GenPersistedServer"

          case get_state(persisted_id) do
            {:ok, initial_state} ->
              case apply(@original, :init, [initial_state]) do
                {:ok, state} ->
                  {:ok, Map.put(state, :persisted_id, persisted_id)}
                other ->
                  other
              end
            error ->
              error
          end
        end

        defp persist_and_update(persisted_id, state) do
          case state do
            {:reply, reply, new_state} ->
              with :ok <- put_state(persisted_id, new_state),
                do: {:reply, reply, Map.put(new_state, :persisted_id, persisted_id)}
            {:reply, reply, new_state, timeout} ->
              with :ok <- put_state(persisted_id, new_state),
                do: {:reply, reply, Map.put(new_state, :persisted_id, persisted_id), timeout}
            {:noreply, new_state} ->
              with :ok <- put_state(persisted_id, new_state),
                do: {:noreply, Map.put(new_state, :persisted_id, persisted_id)}
            {:noreply, new_state, timeout} ->
              with :ok <- put_state(persisted_id, new_state),
                do: {:noreply, Map.put(new_state, :persisted_id, persisted_id), timeout}
            {:stop, reason, reply, new_state} ->
              with :ok <- put_state(persisted_id, new_state),
                do: {:stop, reason, reply, Map.put(new_state, :persisted_id, persisted_id)}
            {:stop, reason, new_state} ->
              with :ok <- put_state(persisted_id, new_state),
                do: {:stop, reason, Map.put(new_state, :persisted_id, persisted_id)}
            # :ok is from code_change
            {:ok, new_state} ->
              with :ok <- put_state(persisted_id, new_state),
                do: {:ok, Map.put(new_state, :persisted_id, persisted_id)}
          end
        end

        def handle_call(msg, from, state) do
          persisted_id = Map.get(state, :persisted_id)
          sub_state = Map.delete(state, :persisted_id)

          case apply(@original, :handle_call, [msg, from, sub_state]) do
            :missing -> super(msg, from, state)
            resp -> persist_and_update(persisted_id, resp)
          end
        end

        def handle_info(msg, state) do
          persisted_id = Map.get(state, :persisted_id)
          sub_state = Map.delete(state, :persisted_id)

          case apply(@original, :handle_info, [msg, sub_state]) do
            :missing -> super(msg, state)
            resp -> persist_and_update(persisted_id, resp)
          end
        end

        def handle_cast(msg, state) do
          persisted_id = Map.get(state, :persisted_id)
          sub_state = Map.delete(state, :persisted_id)

          case apply(@original, :handle_cast, [msg, sub_state]) do
            :missing -> super(msg, state)
            resp -> persist_and_update(persisted_id, resp)
          end
        end

        def terminate(reason, state) do
          persisted_id = Map.get(state, :persisted_id)
          sub_state = Map.delete(state, :persisted_id)

          case apply(@original, :terminate, [reason, sub_state]) do
            :missing -> super(reason, state)
            resp -> persist_and_update(persisted_id, resp)
          end
        end

        def code_change(old, state, extra) do
          persisted_id = Map.get(state, :persisted_id)
          sub_state = Map.delete(state, :persisted_id)

          case apply(@original, :code_change, [old, state, extra]) do
            :missing -> super(old, state, extra)
            resp -> persist_and_update(persisted_id, resp)
          end
        end
      end

      def init(args) do
        {:ok, args}
      end

      def sanitize_state(state), do: state

      def handle_call(_msg, _from, state),
        do: :missing

      def handle_info(_msg, state),
        do: :missing

      def handle_cast(_msg, state),
        do: :missing

      def terminate(_reason, _state),
        do: :missing

      def code_change(_old, state, _extra),
        do: :missing

      defoverridable GenPersistedServer
    end
  end
end
