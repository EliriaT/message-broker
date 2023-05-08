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

  defp parseCommands(line) do
    case String.split(line) do
      ["CREATE", topic] -> {:ok, {:create, topic}}
      ["BEGIN", topic] -> {:ok, {:begin, topic}}
      ["END"] -> {:ok, {:end}}  # to do validate rule , end only after begin
      _ -> {:error, :unknown_command}
    end
  end

  defp runCommand(_command) do
    {:ok, "OK\r\n"}
  end
end
