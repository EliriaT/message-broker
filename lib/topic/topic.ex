defmodule Topic do
  use GenServer, restart: :transient
  require Logger

  def start_link({title}) do
    name = {:via, Registry, {Registry.Topics, title}}
    GenServer.start_link(__MODULE__, {title}, name: name)
  end

  def init({title}) do
    Logger.info("Topic #{inspect(title)} #{inspect(self())} is created...")

    {:ok, %{title: title, subscribers: [], pubrec: [], pubcomp: []}}
  end

  def getSubscribers(pid) do
    GenServer.cast(pid, {:subscribers})
  end

  def addSubscriber(pid, username, socket) do
    GenServer.cast(pid, {:subscribe, username, socket})
  end

  def removeSubscriber(pid, username) do
    GenServer.cast(pid, {:unsubscribe, username})
  end

  def sendMessageToSubs(pid, %{messageID: id, message: message, topic: topic}) do
    GenServer.cast(pid, {:sendMessage, %{messageID: id, message: message, topic: topic}})
  end

  # deadletter channel TODO, I should just store it in the queue state
  def sendMessageToSubs(pid, message) do
    # GenServer.cast(pid, {:sendMessage, message})
  end

  def recConfirm(pid, messageID, username, socket) do
    GenServer.cast(
      pid,
      {:recConfirm, %{messageID: messageID, username: username, socket: socket}}
    )
  end

  def compConfirm(pid, messageID, username, socket) do
    GenServer.cast(
      pid,
      {:compConfirm, %{messageID: messageID, username: username, socket: socket}}
    )
  end

  # add subscriber only if not subscribed early
  def handle_cast({:subscribe, username, socket}, state) do
    state =
      case Enum.member?(Map.get(state, :subscribers), username) do
        true ->
          state

        false ->
          subscribers = state.subscribers
          newSubscriber = %{socket: socket, username: username}
          subscribers = [newSubscriber | subscribers]
          Map.put(state, :subscribers, subscribers)
      end

    {:noreply, state}
  end

  def handle_cast({:unsubscribe, username}, state) do
    filteredSubribers =
      Enum.filter(Map.get(state, :subscribers), fn s -> s[:username] !== username end)

    state = Map.put(state, :subscribers, filteredSubribers)
    {:noreply, state}
  end

  def handle_cast({:subscribers}, state) do
    IO.inspect(state)

    {:noreply, state}
  end

  def handle_cast({:sendMessage, %{messageID: messageId, message: message, topic: topic}}, state) do
    pubMessage = %{"type" => "PUB", "topic" => topic, "msg" => message, "msgId" => messageId}

    pubJson =
      case Jason.encode(pubMessage) do
        {:ok, iodata} -> {:ok, iodata <> "\r\n"}
        {:error, _err} -> {:error, :invalid_map}
      end

    newPubrecEntries =
      Enum.map(Map.get(state, :subscribers), fn subscriber ->
        Process.send_after(
          self(),
          {:checkPubRec,
           %{
             messageID: messageId,
             message: message,
             topic: topic,
             username: subscriber[:username],
             socket: subscriber[:socket]
           }, 0},
          10000
        )

        TCPServer.write_line(subscriber[:socket], pubJson)

        %{
          messageID: messageId,
          received: false,
          username: subscriber[:username],
          socket: subscriber[:socket]
        }
      end)

    pubrecEntries = Map.get(state, :pubrec)

    concat = newPubrecEntries ++ pubrecEntries
    state = Map.put(state, :pubrec, concat)

    {:noreply, state}
  end

  def handle_info(
        {:checkPubRec,
         %{
           messageID: messageId,
           message: message,
           topic: topic,
           username: username,
           socket: socket
         }, count},
        state
      ) do
    pubrecEntries = Map.get(state, :pubrec)

    oneEntry =
      Enum.filter(pubrecEntries, fn e ->
        e[:username] == username and e[:messageID] == messageId
      end)

    state =
      case oneEntry do
        [h | _T] ->
          case h[:received] do
            true ->
              allEntriesFiltered =
                Enum.filter(pubrecEntries, fn e ->
                  e[:username] != username or e[:messageID] != messageId
                end)

              Map.put(state, :pubrec, allEntriesFiltered)

            false ->
              retryPubMessage(
                %{
                  messageID: messageId,
                  message: message,
                  topic: topic,
                  username: username,
                  socket: socket
                },
                count + 1
              )

              state
          end

        [] ->
          state
      end

    {:noreply, state}
  end

  def retryPubMessage(
        %{
          messageID: messageId,
          message: message,
          topic: topic,
          username: username,
          socket: socket
        },
        count
      ) do
    pubMessage = %{"type" => "PUB", "topic" => topic, "msg" => message, "msgId" => messageId}

    pubJson =
      case Jason.encode(pubMessage) do
        {:ok, iodata} -> {:ok, iodata <> "\r\n"}
        {:error, _err} -> {:error, :invalid_map}
      end

    case count do
      5 ->
        Exchanger.sendMessage("deadLetterChan", pubJson)

      _ ->
        Process.send_after(
          self(),
          {:checkPubRec,
           %{
             messageID: messageId,
             message: message,
             topic: topic,
             username: username,
             socket: socket
           }, count},
          10000
        )

        TCPServer.write_line(socket, pubJson)
    end
  end

  def getConsumerPid(username) do
    case Registry.lookup(Registry.Consumers, username) do
      [] ->
        false

      [{pid, _value}] ->
        pid
    end
  end

  def handle_cast(
        {:recConfirm, %{messageID: messageID, username: username, socket: socket}},
        state
      ) do
    pubrecEntries = Map.get(state, :pubrec)

    oneEntry =
      Enum.find(
        pubrecEntries,
        %{messageID: messageID, username: username, received: false},
        fn e ->
          e[:username] == username and e[:messageID] == messageID
        end
      )

    oneEntry = Map.put(oneEntry, :received, true)

    allEntriesFiltered =
      Enum.filter(pubrecEntries, fn e ->
        e[:username] != username or e[:messageID] != messageID
      end)

    state = Map.put(state, :pubrec, [oneEntry | allEntriesFiltered])

    state = newCOMEntry(state, %{messageID: messageID, username: username, socket: socket})
    checkCOMTimeout(%{messageID: messageID, username: username, socket: socket}, 0)
    {:noreply, state}
  end

  def sendREL(%{messageID: messageID, username: _username, socket: socket}) do
    relMessage = %{"type" => "PUBREL", "msgId" => messageID}

    relJson =
      case Jason.encode(relMessage) do
        {:ok, iodata} -> {:ok, iodata <> "\r\n"}
        {:error, _err} -> {:error, :invalid_map}
      end

    TCPServer.write_line(socket, relJson)
  end

  def newCOMEntry(state, %{messageID: messageID, username: username, socket: socket}) do
    pubcompEntries = Map.get(state, :pubcomp)

    oneEntry = %{
      messageID: messageID,
      received: false,
      username: username,
      socket: socket
    }

    state = Map.put(state, :pubcomp, [oneEntry | pubcompEntries])
    state
  end

  def checkCOMTimeout(%{messageID: messageID, username: username, socket: socket}, count) do


    case count do
      5 ->
        # move pointer anyway, because if pubcomp not received, it means there is a problem with the client, and it received the message by acknowledging with pubrec
        nil

      _ ->
        sendREL(%{messageID: messageID, username: username, socket: socket})

        Process.send_after(
          self(),
          {:checkPubComp,
           %{
             messageID: messageID,
             username: username,
             socket: socket
           }, count},
          10000
        )
    end
  end

  def handle_info(
        {:checkPubComp, %{messageID: messageID, username: username, socket: socket}, count},
        state
      ) do
    pubcompEntries = Map.get(state, :pubcomp)

    oneEntry =
      Enum.filter(pubcompEntries, fn e ->
        e[:username] == username and e[:messageID] == messageID
      end)

    state =
      case oneEntry do
        [h | _T] ->
          case h[:received] do
            true ->
              allEntriesFiltered =
                Enum.filter(pubcompEntries, fn e ->
                  e[:username] != username or e[:messageID] != messageID
                end)

              Map.put(state, :pubcomp, allEntriesFiltered)

            false ->
              checkCOMTimeout(
                %{messageID: messageID, username: username, socket: socket},
                count + 1
              )

              state
          end

        [] ->
          state
      end

    {:noreply, state}
  end

  def handle_cast(
        {:compConfirm, %{messageID: messageID, username: username, socket: socket}},
        state
      ) do
    pubcompEntries = Map.get(state, :pubcomp)

    oneEntry =
      Enum.find(
        pubcompEntries,
        %{messageID: messageID, username: username, received: false},
        fn e ->
          e[:username] == username and e[:messageID] == messageID
        end
      )

    oneEntry = Map.put(oneEntry, :received, true)

    allEntriesFiltered =
      Enum.filter(pubcompEntries, fn e ->
        e[:username] != username or e[:messageID] != messageID
      end)

    state = Map.put(state, :pubcomp, [oneEntry | allEntriesFiltered])
    # here I should move the pointer
    IO.puts("Pointer moved!")
    {:noreply, state}
  end
end

# guaranteers in order delivery
# if I were to persist everything, on topic supervisor init, i should read all the topics that previously existed and recreate them, and on exchanger init i should read all the topics as well
# if it is false, it means the connection tcp is interrupted, should try again later
# on login, i should see the last pointer
# case getConsumerPid(username) do
#   false ->
#     nil

#   pid ->
#     Consumer.publishMessage(pid, %{messageID: messageId, message: message, topic: topic})
# end
