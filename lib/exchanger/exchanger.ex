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

  def subscribe(title, socket) do
    GenServer.cast(Exchanger, {:subscribe, title, socket})
  end

  def unsubscribe(title, socket) do
    GenServer.cast(Exchanger, {:unsubscribe, title, socket})
  end

  def sendMessage(topic, message) do
    pid = createTopic(topic)
    Topic.sendMessageToSubs(pid, message)
  end

  # creates if not existent, returns the pid
  def createTopic(title) do
    case isTopicCreated(title) do
      false ->
        {:ok, pid} = TopicSupervisor.start_new_child(title)
        pid

      pid ->
        pid
    end
  end

  def handle_cast({:subscribe, title, socket}, state) do
    pid = createTopic(title)

    Topic.addSubscriber(pid, socket)
    {:noreply, state}
  end

  # unsubscribe from non-existing topics
  def handle_cast({:unsubscribe, title, socket}, state) do
    pid = createTopic(title)

    Topic.removeSubscriber(pid, socket)
    {:noreply, state}
  end
end
