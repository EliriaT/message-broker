defmodule PublisherSupervisor do
  use DynamicSupervisor
  require Logger

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, [], name: PublisherSupervisor)
  end

  # is the supervisor restarting with the same initial state,yes
  def init(_args) do
    Logger.info("PublisherSupervisor is running...")
    DynamicSupervisor.init(strategy: :one_for_one, restart: :temporary)
  end

  # the ID in child spec does not import because it is a dynamic supervisor
  def start_new_child(socket) do
    DynamicSupervisor.start_child(
      PublisherSupervisor,
      {
        Publisher,
        {socket}
      }
    )
  end
end
