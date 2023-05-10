defmodule MessageBroker.MixProject do
  use Mix.Project

  def project do
    [
      app: :message_broker,
      version: "0.1.0",
      escript: escript(),
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      # extra_applications:  (Mix.env() == :prod) && [:logger,:observer] ||  [:logger] ,
      extra_applications:  [:logger] ,
      # it means that when running  iex -S mix, the application will start by calling Application.start(:message_broker), which then invokes the application callback, which in turn starts the supervision tree
      mod: {MessageBroker, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp escript do
    [main_module: MessageBroker]
  end
end
