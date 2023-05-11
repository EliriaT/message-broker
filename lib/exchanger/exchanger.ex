defmodule Exchanger do
  use GenServer, restart: :permanent
  require Logger

  def start_link({}) do
    GenServer.start_link(__MODULE__, {}, name: Exchanger)
  end

  def init({}) do
    Logger.info("Exchanger  #{inspect(self())} is created...")

    # these messages should be persisted. On init, exchanger must read all the persisted messages with their ids. On PUB the message is persisted, on PUBREL deleted and send to the topic.
    # After failure, if the message is still existent, it means the publisher did not receive a PUBCOMP, which means it will send a PUBREL again
    {:ok, %{messages: []}}
  end

  def pubRelPublisher(messageId) do
    GenServer.cast(Exchanger, {:PublisherPUBREL, messageId})
  end

  def storeMessage(messageId, message, topic) do
    GenServer.cast(Exchanger, {:store, messageId, message, topic})
  end

  # def removeMessage(messageId) do
  #   GenServer.cast(Exchanger, {:remove, messageId})
  # end

  # def getMessage(messageId) do
  #   GenServer.cast(Exchanger, {:get, messageId})
  # end

  def isTopicCreated(title) do
    case Registry.lookup(Registry.Topics, title) do
      [] ->
        false

      [{pid, _value}] ->
        pid
    end
  end

  def subscribe(title, username,socket) do
    GenServer.cast(Exchanger, {:subscribe, title, username, socket})
  end

  def unsubscribe(title, username) do
    GenServer.cast(Exchanger, {:unsubscribe, title, username})
  end

  def sendMessage("deadLetterChan", message) do
    pid = createTopic("deadLetterChan")
    Topic.sendMessageToSubs(pid, message)
  end

  def sendMessage(topic, %{messageID: id, message: message, topic: topic}) do
    pid = createTopic(topic)
    Topic.sendMessageToSubs(pid, %{messageID: id, message: message, topic: topic})
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

  def removeMessage(messageId, state) do
    messages = Map.get(state, :messages)

    messages = Enum.filter(messages, fn m -> Map.get(m, :messageID) != messageId end)

    messages
  end

  # on PUBREL what is no message with this ID?
  # then nothing will happen, no message will be sent to publisher
  # error handling is more complex here
  def getMessage(messageId, state) do
    messages = Map.get(state, :messages)

    case Enum.filter(messages, fn m -> Map.get(m, :messageID) == messageId end) do
      [m | _] ->
        %{
          messageID: Map.get(m, :messageID),
          message: Map.get(m, :message),
          topic: Map.get(m, :topic)
        }

      [] ->
        nil
    end
  end

  def handle_cast({:subscribe, title, username, socket}, state) do
    pid = createTopic(title)

    Topic.addSubscriber(pid, username, socket)
    {:noreply, state}
  end

  def handle_cast({:unsubscribe, title, username}, state) do
    pid = createTopic(title)

    Topic.removeSubscriber(pid, username)
    {:noreply, state}
  end

  def handle_cast({:store, messageId, message, topic}, state) do
    message = %{
      messageID: messageId,
      message: message,
      topic: topic
    }

    messages = Map.get(state, :messages)

    state = Map.put(state, :messages, [message | messages])

    {:noreply, state}
  end

  def handle_cast({:PublisherPUBREL, messageId}, state) do
    case getMessage(messageId, state) do
      %{messageID: id, message: message, topic: topic} ->
        sendMessage(topic, %{messageID: id, message: message, topic: topic})

      nil ->
        nil
    end

    state = Map.put(state, :messages, removeMessage(messageId, state))

    {:noreply, state}
  end
end
