defmodule Topic do
  use GenServer, restart: :transient
  require Logger

  def start_link({title}) do
    name = {:via, Registry, {Registry.Topics, title}}
    GenServer.start_link(__MODULE__, {title}, name: name)
  end

  def init({title}) do
    Logger.info("Topic #{inspect(title)} #{inspect(self())} is created...")

    {:ok, %{title: title, subscribers: []}}
  end

  def getSubscribers(pid) do
    GenServer.cast(pid, {:subscribers})
  end

  def addSubscriber(pid, socket) do
    GenServer.cast(pid, {:subscribe, socket})
  end

  # add subscriber only if not subscribed early
  def handle_cast({:subscribe, socket}, state) do
    state =
      case Enum.member?(Map.get(state, :subscribers), socket) do
        true ->
          state

        false ->
          subscribers = state.subscribers
          subscribers = [socket | subscribers]
          Map.put(state, :subscribers, subscribers)
      end

    {:noreply, state}
  end

  def handle_cast({:subscribers}, state) do
    IO.inspect(state)

    {:noreply, state}
  end
end

# if I were to persist everything, on topic supervisor init, i should read all the topics that previously existed and recreate them, and on exchanger init i should read all the topics as well
