# MessageBroker

A simple message broker implemented in Elixir, based on the actor concurrency model.

Implemented:
* Durable queues
* Persistent messages
* MQTT QoS2
* Publish retrial
* Represents a TCP server
* Dead letter channel
* Run with executable / docker 

## Supervision Tree
![ast](https://github.com/EliriaT/message-broker/blob/main/Diagrams/Lab3SupervisionTree.png)


## Message Flow Diagram
![ast](https://github.com/EliriaT/message-broker/blob/main/Diagrams/MessageFlow.png)


## MQTT QoS2 Message Flow Diagram
![ast](https://github.com/EliriaT/message-broker/blob/main/Diagrams/QoS2.png)

## MQTT QoS2 Retrial Message Flow Diagram
![ast](https://github.com/EliriaT/message-broker/blob/main/Diagrams/QoS2Retrial.png)

## Run the app:
`mix run --no-halt`

or

`iex -S mix`

or

```
mix escript.build
./message_broker
```

or

`docker run --name message-broker -it --rm  -p 4040:4040  -p 4041:4041 elixir-mb:latest`

## Useful commands:
`sudo lsof -i -P -n | grep LISTEN` - Check ports that are on LISTEN

`Supervisor.which_children( TopicAndRegistrySupervisor)` - Check children of a supervisor

`:observer.start` - inspect processes, sockets, supervisors

`mix escript.build` - build the executable

`./message_broker` - run the executable

`docker build -t elixir-mb .` - build the docker image

`docker run --name message-broker -it --rm  -p 4040:4040  -p 4041:4041 elixir-mb:latest`  - run the docker image


## Some notes

1. If a consumer is disconnected, his last sent message is persisted on the message broker side. But in order to retrieve the messages that were lost while the consumer was disconnected or unsubscribed, the consumer MUST again subscribe to each topic it previously unsubscribed or all topics if disconnected. Message broker does not implement right now consumer to topics storage. There is only a topic to consumers storage and relation. If message broker detects that the consumer is disconnected, it unsubsribes the consumer, but stores the index of the last sent message. On subscribe, if this index is found present, the message broker (the topic actor) will start sending message by message from the last message index. If the consumer will not subscribe again, he will not receive even the latest messages.

2. Topic will detect consumer disconnection by failing to publish a message to consumer

3. For future to dos, I can store in the local db usernames to topics storage

4. Topic created only when a consumer subscribes to it


