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
              runCommand(command, socket)

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
    line = String.downcase(line)

    case String.split(line) do
      ["create", topic] -> {:ok, {:create, topic}}
      ["pub", topic] -> {:ok, {:pub, topic}}
      _ -> {:error, :unknown_command}
    end
  end

  defp receiveMessage(topic, message, socket) do
    case TCPServer.read_line(socket) do
      {:ok, line} ->
        case String.split(line) do
          ["end"] ->
            Exchanger.sendMessage(topic, message)

          _ ->
            message = message <> line
            receiveMessage(topic, message, socket)
        end

      {:error, errMessage} = err ->
        message = message <> errMessage
        Exchanger.sendMessage("deadLetterChan", message)
        TCPServer.write_line(socket, err)
    end
  end

  defp runCommand(command, socket) do
    case command do
      {:create, topic} ->
        Exchanger.createTopic(topic)
        {:ok, "OK\r\n"}

      {:pub, topic} ->
        receiveMessage(topic, "", socket)
        {:ok, "OK\r\n"}

      _ ->
        {:ok, "NOT IMPLEMENTED\r\n"}
    end
  end
end
