defmodule Topic do
  use GenServer, restart: :permanent
  require Logger

  def start_link({title}) do
    name = {:via, Registry, {Registry.Topics, title}}
    GenServer.start_link(__MODULE__, {title}, name: name)
  end

  def init({title}) do
    Logger.info("Topic #{inspect(title)} #{inspect(self())} is created...")

    PersistentEts.new(String.to_atom(title), "./lib/topic/topics-db/#{title}.tab", [
      :set,
      :named_table,
      :public
    ])

    messages = getMessagesFromDB(title)

    {:ok,
     %{
       title: title,
       subscribers: [],
       pubrec: [],
       pubcomp: [],
       messages: messages,
       subscribedIndexes: [],
       unSubscribedIndexes: []
     }}
  end

  # index %{username: "sdf", index: -1}

  # on subscribe check if not present in subscribers, then add it. Check if not present in subscribedIndexes, then check if not present in unSubscribedIndexes, if present add it from unsub list to sub list, if no, create a new one with index 0.
  # on unsubscribe get the index from subscribedIndexes and put it in unSubscribedIndexes, it should remain in subscribers list
  # if unsubscribed permanently is implemented,   I should delete the subscriber from the subscriber list and delete its index from subscribedIndexes
  # on connection disconnected I should move the index from subscribed to unsubcribed
  def getSubscribers(pid) do
    GenServer.cast(pid, {:subscribers})
  end

  def addSubscriber(pid, username, socket) do
    GenServer.cast(pid, {:subscribe, username, socket})
  end

  def removeSubscriber(pid, username) do
    GenServer.cast(pid, {:unsubscribe, username})
  end

  def sendMessageToONESub(pid, %{messageID: id, message: message, topic: topic}, %{
        username: username,
        socket: socket
      }) do
    GenServer.cast(
      pid,
      {:sendMessageToSub, %{messageID: id, message: message, topic: topic},
       %{username: username, socket: socket}}
    )
  end

  def sendMessageToSubs(pid, %{messageID: id, message: message, topic: topic}) do
    GenServer.cast(pid, {:sendMessage, %{messageID: id, message: message, topic: topic}})
  end

  # this will only be reached by the deadLetterChan
  # saveMessageInDB(String.to_atom("deadLetterChan"), message)
  def sendMessageToSubs(pid, message) do
    # just add the message in the local queue and store it

    # I should send the message to intersted subscribers. But for now the dead letter chan will only store the messages. No sending.
  end

  def getMessagesFromDB(title) do
    messages =
      case :ets.lookup(String.to_atom(title), "messages") do
        [{"messages", list}] ->
          # append a new message at the end of the list
          list

        [] ->
          []
      end

    messages
  end

  def saveMessageInDB(title, message) do
    newList =
      case :ets.lookup(String.to_atom(title), "messages") do
        [{"messages", list}] ->
          # append a new message at the end of the list
          [message | list]

        [] ->
          [message]
      end

    :ets.insert(String.to_atom(title), {"messages", newList})
    PersistentEts.flush(String.to_atom(title))
  end

  def storeMessageInternally(pid, message) do
    GenServer.call(pid, {:storeMessageIntern, message})
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

  # here I have to reindex and subscribedIndexes and unSubscribedIndexes
  def handle_call({:storeMessageIntern, message}, from, state) do
    messages = Map.get(state, :messages, [])
    messages = [message | messages]
    state = Map.put(state, :messages, messages)

    subscribedIndexes = Map.get(state, :subscribedIndexes)

    subscribedIndexes =
      Enum.map(subscribedIndexes, fn sub ->
        case Map.get(sub, :index) do
          -1 ->
            Map.put(sub, :index, sub[:index] + 1)
            # sub

          _ ->
            Map.put(sub, :index, sub[:index] + 1)
        end
      end)

    unSubscribedIndexes = Map.get(state, :unSubscribedIndexes)

    unSubscribedIndexes =
      Enum.map(unSubscribedIndexes, fn sub -> Map.put(sub, :index, sub[:index] + 1) end)

    state = Map.put(state, :unSubscribedIndexes, unSubscribedIndexes)
    state = Map.put(state, :subscribedIndexes, subscribedIndexes)

    {:reply, :done, state}
  end

  # add subscriber only if not subscribed early
  def handle_cast({:subscribe, username, socket}, state) do
    state =
      case Enum.find(Map.get(state, :subscribers), fn sub -> sub[:username] == username end) do
        nil ->
          subscribers = state.subscribers
          newSubscriber = %{socket: socket, username: username}
          subscribers = [newSubscriber | subscribers]
          Map.put(state, :subscribers, subscribers)

        _ ->
          state
      end

    # unSubscribedIndexes
    state =
      case Enum.find(Map.get(state, :subscribedIndexes), fn sub -> sub[:username] == username end) do
        nil ->
          # if not present in subscribed indexex, it means it wasn't disconnected accidentaly, and check in unsubscribedIndexes
          state =
            case Enum.find(Map.get(state, :unSubscribedIndexes), fn sub ->
                   sub[:username] == username
                 end) do
              nil ->
                # create a new index map in subscribedIndexes
                newIndex = %{username: username, index: -1}
                subscribedIndexes = Map.get(state, :subscribedIndexes)
                subscribedIndexes = [newIndex | subscribedIndexes]
                state = Map.put(state, :subscribedIndexes, subscribedIndexes)
                state

              unSubIndex ->
                # move index from unsubscribed to the subscribed list

                subscribedIndexes = Map.get(state, :subscribedIndexes)
                subscribedIndexes = [unSubIndex | subscribedIndexes]
                state = Map.put(state, :subscribedIndexes, subscribedIndexes)

                # delete index from unsubscribed index list
                unSubscribedIndexes = Map.get(state, :unSubscribedIndexes)

                unSubscribedIndexes =
                  Enum.filter(unSubscribedIndexes, fn unSub -> unSub[:username] !== username end)

                state = Map.put(state, :unSubscribedIndexes, unSubscribedIndexes)

                # CHECK if index is not -1, start sending the last not received message
                case unSubIndex[:index] do
                  -1 ->
                    nil

                  indx ->
                    messages = Map.get(state, :messages)
                    message = Enum.at(messages, indx)

                    sendMessageToONESub(self(), message, %{
                      username: username,
                      socket: socket
                    })
                end

                state
            end

          state

        _ ->
          state
      end

    {:noreply, state}
  end

  # on unsubscribe get the index from subscribedIndexes and put it in unSubscribedIndexes
  # it should not remain in general subscribers list, because the messages must not be sent to this subscriber

  def handle_cast({:unsubscribe, username}, state) do
    filteredSubribers =
      Enum.filter(Map.get(state, :subscribers), fn s -> s[:username] !== username end)

    state = Map.put(state, :subscribers, filteredSubribers)

    state =
      case Enum.find(Map.get(state, :subscribedIndexes), fn sub -> sub[:username] == username end) do
        nil ->
          # it means unfortunately that there was a strange bug error on subscribing , this should not happen
          state

        subIndex ->
          unSubscribedIndexes = Map.get(state, :unSubscribedIndexes)
          unSubscribedIndexes = [subIndex | unSubscribedIndexes]
          state = Map.put(state, :unSubscribedIndexes, unSubscribedIndexes)

          subscribedIndexes = Map.get(state, :subscribedIndexes)

          subscribedIndexes =
            Enum.filter(subscribedIndexes, fn sub -> sub[:username] !== username end)

          state = Map.put(state, :subscribedIndexes, subscribedIndexes)

          state
      end

    {:noreply, state}
  end

  def handle_cast({:subscribers}, state) do
    IO.inspect(state)

    {:noreply, state}
  end

  # send a message to only one subscriber
  def handle_cast(
        {:sendMessageToSub, %{messageID: messageId, message: message, topic: topic},
         %{username: username, socket: socket}},
        state
      ) do
    pubMessage = %{"type" => "PUB", "topic" => topic, "msg" => message, "msgId" => messageId}

    pubJson =
      case Jason.encode(pubMessage) do
        {:ok, iodata} -> {:ok, iodata <> "\r\n"}
        {:error, _err} -> {:error, :invalid_map}
      end

    newPubrecEntries =
      Enum.map([%{username: username, socket: socket}], fn subscriber ->
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

  # send a recent message to all recent subscribers at index 0
  def handle_cast({:sendMessage, %{messageID: messageId, message: message, topic: topic}}, state) do
    pubMessage = %{"type" => "PUB", "topic" => topic, "msg" => message, "msgId" => messageId}

    pubJson =
      case Jason.encode(pubMessage) do
        {:ok, iodata} -> {:ok, iodata <> "\r\n"}
        {:error, _err} -> {:error, :invalid_map}
      end

    # select only subscribers with index 0
    subscribedIndexes = Map.get(state, :subscribedIndexes)

    latestSubscribers =
      Enum.filter(Map.get(state, :subscribers), fn subscriber ->
        oneIndex =
          Enum.find(subscribedIndexes, fn sub -> sub[:username] == subscriber[:username] end)

        oneIndex[:index] == 0
      end)

    newPubrecEntries =
      Enum.map(latestSubscribers, fn subscriber ->
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
        # here I should instead unsubscribe the user
        removeSubscriber(self(), username)

      # Exchanger.sendMessage("deadLetterChan", pubJson)

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

    # here I should move the pointer by decreasing it with one
    # the latest message has index 0
    subscribedIndexes = Map.get(state, :subscribedIndexes)

    filteredSubscribedIndexes =
      Enum.filter(subscribedIndexes, fn sub -> sub[:username] != username end)

    oneIndex = Enum.find(subscribedIndexes, fn sub -> sub[:username] == username end)

    # index will become -1 if the consumer is up to date with messages
    index =oneIndex[:index] - 1
      # if oneIndex[:index] == -1 do
      #   oneIndex[:index]
      # else
      #   ind = oneIndex[:index] - 1
      #   ind
      # end

    subscribedIndexes = [
      %{username: oneIndex[:username], index: index} | filteredSubscribedIndexes
    ]

    state = Map.put(state, :subscribedIndexes, subscribedIndexes)

    # check if index is -1, if not, start sending the next message
    case index do
      -1 ->
        nil

      indx ->
        messages = Map.get(state, :messages)
        message = Enum.at(messages, indx)

        sendMessageToONESub(self(), message, %{
          username: username,
          socket: socket
        })
    end

    IO.puts("Pointer moved! Next message sent if present!")
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
