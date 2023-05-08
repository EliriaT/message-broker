defmodule TopicSupervisor do
  use DynamicSupervisor
  require Logger

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, [], name: TopicSupervisor)
  end

  # What if the registry crashes but topic supervisor alive?
  def init(_args) do
    Logger.info("TopicSupervisor is running...")
    DynamicSupervisor.init(strategy: :one_for_one, restart: :transient)
  end

  def start_new_child(title) do
    DynamicSupervisor.start_child(
      TopicSupervisor,
      {
        Topic,
        {title}
      }
    )

  end
end
