defmodule Consumer do
  use GenServer, restart: :temporary
  require Logger

  def start_link({socket}) do
    GenServer.start_link(__MODULE__, {socket})
  end

  def init({socket}) do
    Logger.info("Consumer #{inspect(self())} is created...")

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

  # commands are case insensitive
  defp parseCommands(line) when is_binary(line) do
    line = String.downcase(line)

    case String.split(line) do
      ["sub", topic] -> {:ok, {:subscribe, topic}}
      ["unsub", topic] -> {:ok, {:unsubscribe, topic}}
      _ -> {:error, :unknown_command}
    end
  end

  defp runCommand(command, socket) do
    case command do
      {:subscribe, topic} ->
        # Should the subscribe be asynchronous or synchronous? if async I can return ok or if not ok
        Exchanger.subscribe(topic, socket)
        {:ok, "OK\r\n"}

      {:unsubscribe, topic} ->
        Exchanger.unsubscribe(topic, socket)
        {:ok, "OK\r\n"}

      _ ->
        {:ok, "NOT IMPLEMENTED\r\n"}
    end
  end
end
