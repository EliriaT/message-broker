defmodule TopicAndRegistrySupervisor do
  use Supervisor

  def start_link(_l) do
    Supervisor.start_link(__MODULE__, {}, name: TopicAndRegistrySupervisor)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {TopicSupervisor, 0},
      {Registry, keys: :unique, name: Registry.Topics}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end

# if the topic supervisor crashes, registry should also crash because otherwise the title will not be able to reregister themselves
# if the register crashes, topics must also crash and reregister themselves and restore their state on init
