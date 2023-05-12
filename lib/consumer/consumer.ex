defmodule Consumer do
  use GenServer, restart: :temporary
  require Logger

  def start_link({socket}) do
    GenServer.start_link(__MODULE__, {socket})
  end

  def init({socket}) do
    Logger.info("Consumer #{inspect(self())} is created...")

    {:ok, %{socket: socket, name: "", pubrec: [], pubcomp: []}}
  end

  def serveSocket(pid) do
    GenServer.cast(pid, {:serve})
  end

  def selfServeSockerLoop(pid) do
    GenServer.cast(pid, {:serveLoop})
  end

  def handle_cast({:serve}, state) do
    socket = state.socket
    # before serving the client, it must login
    username = askToLogin(socket, 0)

    case Registry.register(Registry.Consumers, username, []) do
      {:ok, _} ->
        TCPServer.write_line(socket, {:ok, "Succesfully logged in!\r\n"})
        nil

      {:error, {:already_registered, _p}} ->
        TCPServer.write_line(socket, {:error, "A connection for this username already exists"})
    end

    state = Map.put(state, :name, username)

    serveLoop(socket, username)

    {:noreply, state}
  end

  def handle_cast({:serveLoop}, state) do
    serveLoop(state.socket, state.name)

    {:noreply, state}
  end

  def askToLogin(socket, 5) do
    TCPServer.write_line(socket, {:error, "Unknown login error"})
    exit(:no_login)
  end

  # login would ideally be an UUID
  def askToLogin(socket, num) do
    TCPServer.write_line(socket, {:ok, "Please login!\r\n"})

    case TCPServer.read_line(socket) do
      {:ok, line} ->
        line = String.downcase(line)

        case String.split(line) do
          ["log", username] ->

            username

          _ ->
            askToLogin(socket, num + 1)
        end

      {:error, _} = err ->
        TCPServer.write_line(socket, err)
        askToLogin(socket, num + 1)
    end
  end

  defp serveLoop(socket, username) do
    command =
      case TCPServer.read_line(socket) do
        {:ok, line} ->
          case parseCommands(line) do
            {:ok, command} ->
              runCommand(command, username, socket)

            {:error, _} = err ->
              err
          end

        {:error, _} = err ->
          err
      end

    TCPServer.write_line(socket, command)

    # send a message back to itself so that this function will be called again. I need this because of the timer per topic configuration
    selfServeSockerLoop(self())
  end

  # commands are case insensitive
  defp parseCommands(line) when is_binary(line) do
    # line = String.downcase(line)
    command =
      case Jason.decode(line) do
        {:ok, map} ->
          map

        {:error, error} ->
          error
      end

    case command do
      %{"type" => "SUB", "topic" => topic} ->
        {:ok, {:subscribe, topic}}

      %{"type" => "UNSUB", "topic" => topic} ->
        {:ok, {:unsubscribe, topic}}

      %{"type" => "PUBREC", "msgId" => messageId, "topic" => topic} ->
        {:ok, {:pubrec, messageId, topic}}

      %{"type" => "PUBCOMP", "msgId" => messageId, "topic" => topic} ->
        {:ok, {:pubcomp, messageId, topic}}

      %Jason.DecodeError{} ->
        {:error, {:invalid_json, line}}

      _ ->
        # save the command in dead letter channel
        {:error, {:unknown_command, line}}
    end
  end

  defp runCommand(command, username, socket) do
    case command do
      {:subscribe, topic} ->
        # Should the subscribe be asynchronous or synchronous? if async I can return ok or if not ok
        Exchanger.subscribe(topic, username, socket)
        {:ok, "OK\r\n"}

      {:unsubscribe, topic} ->
        Exchanger.unsubscribe(topic, username)
        {:ok, "OK\r\n"}

      {:pubrec, messageId, topic} ->
        # confirm message receiving
        pid = Exchanger.createTopic(topic)
        Topic.recConfirm(pid, messageId, username, socket)
        {:ok, "OK\r\n"}

      {:pubcomp, messageId, topic} ->
        pid = Exchanger.createTopic(topic)
        Topic.compConfirm(pid, messageId, username, socket)
        {:ok, "OK\r\n"}

      _ ->
        {:ok, "NOT IMPLEMENTED\r\n"}
    end
  end
end
