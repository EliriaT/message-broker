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