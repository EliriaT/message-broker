defmodule TCPServer do
  require Logger

  def accept(port, type) do
    # The options below mean:
    #
    # 1. `:binary` - receives data as binaries (instead of lists)
    # 2. `packet: :line` - receives data line by line
    # 3. `active: false` - blocks on `:gen_tcp.recv/2` until data is available, in other words, the read is synchronous
    # 4. `reuseaddr: true` - allows us to reuse the address if the listener crashes

    #
    {:ok, socket} =
      :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true])

    Logger.info("Server #{type} accepting connections on port #{port}")
    loop_acceptor(socket)
  end

  defp loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)

    {:ok, pid} = Task.Supervisor.start_child(TCPServer.TaskSupervisor, fn -> serve(client) end)

    # this ensures that messages will be send to process pid, but not to the actor that accepted the socket connection. Also ensures that the acceptor
    # will not bring down the clients on crash. Sockets are not tied to the process that accepted them
    # if the tcp acceptor server crashes, the connections are not crashed
    :ok = :gen_tcp.controlling_process(client, pid)

    loop_acceptor(socket)
  end

  defp serve(socket) do
    # probably each individual actor will have to have this serve
    socket
    |> read_line()
    |> write_line(socket)

    serve(socket)
  end

  defp read_line(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        data

        # {:error, :closed} ->
        #   "closed"

        # {:error, :enotconn} ->
        #   nil
    end
  end

  defp write_line(line, socket) do
    :gen_tcp.send(socket, line)
  end
end
