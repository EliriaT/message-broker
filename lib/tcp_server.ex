defmodule TCPServer do
  require Logger

  def accept(port, type) do
    # The options below mean:
    #
    # 1. `:binary` - receives data as binaries (instead of lists)
    # 2. `packet: :line` - receives data line by line
    # 3. `active: false` - blocks on `:gen_tcp.recv/2` until data is available, in other words, the read is synchronous
    # 4. `reuseaddr: true` - allows us to reuse the address if the listener crashes

    {:ok, socket} =
      :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true])

    Logger.info("Server #{type} accepting connections on port #{port}")
    loop_acceptor(socket, type)
  end

  defp loop_acceptor(socket, type) do
    {:ok, client} = :gen_tcp.accept(socket)

    pid =
      case type do
        :publisher ->
          {:ok, pid} = PublisherSupervisor.start_new_child(client)
          # start serving the connection
          Publisher.serveSocket(pid)
          pid

        :consumer ->
          {:ok, pid} = ConsumerSupervisor.start_new_child(client)
          # start serving the connection
          Consumer.serveSocket(pid)
          pid
      end

    # this ensures that messages will be send to process pid, but not to the actor that accepted the socket connection. Also ensures that the acceptor
    # will not bring down the clients on crash. Sockets are not tied to the process that accepted them
    # if the tcp acceptor server crashes, the connections are not crashed
    :ok = :gen_tcp.controlling_process(client, pid)

    loop_acceptor(socket, type)
  end

  def read_line(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        {:ok, data}

      {:error, _} = err ->
        err
    end
  end

  def write_line(socket, {:ok, text}) do
    :gen_tcp.send(socket, text)
  end

  def write_line(socket, {:error, :unknown_command}) do
    # Known error; write to the client
    :gen_tcp.send(socket, "UNKNOWN COMMAND\r\n")
  end

  # aici se vede ca consumerul s-a deconectat
  def write_line(_socket, {:error, :closed}) do
    # The connection was closed, exit politely
    IO.puts("Connection on process #{inspect(self())} closed by client")
    exit(:shutdown)

  end

  def write_line(socket, {:error, error}) do
    # Unknown error; write to the client and exit
    :gen_tcp.send(socket, "ERROR\r\n")
    exit(error)
  end
end
