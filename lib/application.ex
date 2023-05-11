defmodule MessageBroker do
  use Application

  # this application is a supervisor in itself
  @impl true
  def start(_type, _args) do
    # IO.puts( Mix.env())
    # if Mix.env() == :dev do
    :observer.start()
    #   IO.puts( Mix.env())
    # end

    consumerPort = 4040
    publisherPort = 4041

    children = [
      {PublisherSupervisor, {}},
      {ConsumerAndRegistrySupervisor, {}},
      {TopicAndRegistrySupervisor, {}},
      {Exchanger, {}},

      # The server must be permanently started, if it crashes, the supervisor will start it again
      Supervisor.child_spec({Task, fn -> TCPServer.accept(publisherPort, :publisher) end},
        restart: :permanent,
        id: :publisherServer
      ),
      Supervisor.child_spec({Task, fn -> TCPServer.accept(consumerPort, :consumer) end},
        restart: :permanent,
        id: :consumerServer
      )
    ]

    opts = [strategy: :one_for_one, name: MessageBroker.Supervisor]
    Supervisor.start_link(children, opts)

    TopicSupervisor.start_new_child("deadLetterChan")
  end

  def main(_args \\ []) do
    start({}, {})

    receive do
      _ -> IO.inspect("Hi")
    end
  end
end
