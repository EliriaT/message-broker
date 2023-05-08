defmodule Exchanger do
  use GenServer, restart: :permanent
  require Logger

  def start_link({}) do
    GenServer.start_link(__MODULE__, {}, name: Exchanger)
  end

  def init({}) do
    Logger.info("Exchanger  #{inspect(self())} is created...")

    {:ok, %{}}
  end

  def isTopicCreated(title) do
    case Registry.lookup(Registry.Topics, title) do
      [] ->
        false

      [{pid, _value}] ->
        pid
    end
  end

  # if already subscribed
  def subscribe(title, socket) do
    GenServer.cast(Exchanger, {:subscribe, title, socket})
  end

  def handle_cast({:subscribe, title, socket}, state) do
    pid = case isTopicCreated(title)  do
      false ->
        {:ok, pid} = TopicSupervisor.start_new_child(title)
        pid
      pid ->
        pid
    end

    Topic.addSubscriber(pid, socket)
    {:noreply, state}
  end
end
