defmodule ConsumerAndRegistrySupervisor do
  use Supervisor

  def start_link(_l) do
    Supervisor.start_link(__MODULE__, {}, name: ConsumerAndRegistrySupervisor)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {ConsumerSupervisor, 0},
      {Registry, keys: :unique, name: Registry.Consumers}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end

# if the consumer supervisor crashes, registry should also crash because otherwise the consumers will not be able to reregister themselves
# if the register crashes, consumers must also crash and reregister themselves and restore their state on init
