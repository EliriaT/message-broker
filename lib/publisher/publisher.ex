defmodule Publisher do
  use GenServer, restart: :temporary
  require Logger

  def start_link({socket}) do
    GenServer.start_link(__MODULE__, {socket})
  end

  def init({socket}) do
    Logger.info("Publisher #{inspect(self())} is created...")

    {:ok, %{socket: socket}}
  end

  def serveSocket(pid) do
    GenServer.cast(pid, {:serve})
  end

  def sendPUBREC(messageId) do
    pubrec = %{
      type: "PUBREC",
      msgId: messageId
    }

    case Jason.encode(pubrec) do
      # here
      {:ok, iodata} -> {:ok, iodata<> "\r\n" }
      {:error, _err} -> {:error, :invalid_map}
    end
  end

  def sendPUBCOMP(messageId) do
    pubcom = %{
      type: "PUBCOMP",
      msgId: messageId
    }

    case Jason.encode(pubcom) do
      {:ok, iodata} -> {:ok, iodata <> "\r\n"}
      {:error, _err} -> {:error, :invalid_map}
    end
  end

  def handle_cast({:serve}, state) do
    socket = state.socket
    serveLoop(socket)
  end

  defp serveLoop(socket) do
    command =
      case TCPServer.read_line(socket) do
        {:ok, line} ->
          case parseCommands(line) do
            {:ok, command} ->
              runCommand(command)

            {:error, _} = err ->
              err
          end

        {:error, _} = err ->
          err
      end

    TCPServer.write_line(socket, command)

    serveLoop(socket)
  end

  defp parseCommands(line) when is_binary(line) do
    command =
      case Jason.decode(line) do
        {:ok, map} ->
          map

        {:error, error} ->
          error
      end

    case command do
      # ["create", topic] -> {:ok, {:create, topic}}
      %{"type" => "PUB", "topic" => topic, "msg" => message} ->
        {:ok, {:pub, topic, message}}

      %{"type" => "PUBREL", "msgId" => msgId} ->
        {:ok, {:pubrel, msgId}}

      %Jason.DecodeError{} ->
        # save the command in dead letter channel
        {:error, {:invalid_json, line}}

      _ ->
        # save the command in dead letter channel
        {:error, {:unknown_command, line}}
    end
  end

  defp runCommand(command) do
    case command do
      {:pub, topic, message} ->
        messageId =:rand.uniform(1)   #65535
        Exchanger.storeMessage(messageId, message, topic)
        # this will return the pubrec
        sendPUBREC(messageId)

      {:pubrel, msgId} ->
        # here immedietely the message will be persisted, after this pubcomp sent
        Exchanger.pubRelPublisher(msgId)
        sendPUBCOMP(msgId)

      _ ->
        {:ok, "NOT IMPLEMENTED\r\n"}
    end
  end
end
