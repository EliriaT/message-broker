defmodule MessageBroker do
  use Application

  # this application is a supervisor in itself
  @impl true
  def start(_type, _args) do
    :observer.start
    
    consumerPort = 4040
    publisherPort = 4041

    children = [
      {PublisherSupervisor, {}},
      {ConsumerSupervisor, {}},
      {TopicAndRegistrySupervisor, {}},
      {Exchanger,{}},


      # The server must be permanently started, if it crashes, the supervisor will start it again
      Supervisor.child_spec({Task, fn -> TCPServer.accept(publisherPort, :publisher) end},
        restart: :permanent,
        id: :publisherServer,
      ),
      Supervisor.child_spec({Task, fn -> TCPServer.accept(consumerPort, :consumer) end},
        restart: :permanent,
        id: :consumerServer
      )
    ]

    opts = [strategy: :one_for_one, name: MessageBroker.Supervisor]
    Supervisor.start_link(children, opts)

    # MessageBroker.Supervisor.start_link([])
  end
end
