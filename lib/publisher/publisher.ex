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
    processCommand(socket)
  end

  defp processCommand(socket) do
    command =
      socket
      |> TCPServer.read_line()

    TCPServer.write_line(socket,command)

    processCommand(socket)
  end
end
