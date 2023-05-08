defmodule MessageBroker do
  use Application

  @impl true
  def start(_type, _args) do
    port = String.to_integer(System.get_env("PORT") || "4040")

    children = [
      {PublisherSupervisor, name: PublisherSupervisor},
      # {Task.Supervisor, name: TCPServer.TaskSupervisor},

      # The server must be permanently started, if it crashes, the supervisor will start it again
      Supervisor.child_spec({Task, fn -> TCPServer.accept(port,:publisher) end}, restart: :permanent)
    ]

    opts = [strategy: :one_for_one, name: MessageBroker.Supervisor]
    Supervisor.start_link(children, opts)

    # MessageBroker.Supervisor.start_link([])
  end

end
