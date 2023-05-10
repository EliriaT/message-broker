# MessageBroker

**TODO: Add description**

## Run the app:
`mix run --no-halt`
`iex -S mix`
`PORT=4040 mix run --no-halt`

## Useful commands:
`sudo lsof -i -P -n | grep LISTEN` - Check ports that are on LISTEN
`Supervisor.which_children( TopicAndRegistrySupervisor)` - Check children of a supervisor
`:observer.start` - inspect processes, sockets, supervisors
`mix escript.build` - build the executable
`./message_broker` - run the executable
`docker build -t elixir-mb .` - build the docker image
`docker run --name message-broker -it --rm  -p 4040:4040  -p 4041:4041 elixir-mb:latest`  - run the docker image