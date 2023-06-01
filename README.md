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
* Multiple topics, multiple subscribers, multiple publisher
* Fault tolerance thanks to supervisors

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

3. For future to dos, I can store in the local db topic to usernames storage in the Exchanger. This will allow receiving lost messages after disconnection, without the neccessity to subscribe to previously subscribed topics. The exchanger will subscribe the consumer without it doing it by itself.

4. Topic is created only when a consumer subscribes to it

## Demo using telnet 
1. Build and run the app:

```
mix escript.build
./message_broker
```

2. Applications logs:
```
Generated escript message_broker with MIX_ENV=dev

(Erlang:17286): Gtk-WARNING **: 11:45:55.874: Drawing a gadget with negative dimensions. Did you forget to allocate a size? (node tab owner GtkNotebook)

(Erlang:17286): Gtk-WARNING **: 11:45:55.888: Drawing a gadget with negative dimensions. Did you forget to allocate a size? (node tab owner GtkNotebook)

11:45:55.883 [info]  PublisherSupervisor is running...

11:45:55.891 [info]  ConsumerSupervisor is running...

11:45:55.902 [info]  TopicSupervisor is running...

11:45:55.907 [info]  Exchanger  #PID<0.131.0> is created...

11:45:55.915 [info]  Topic "deadLetterChan" #PID<0.132.0> is created...

11:45:55.960 [info]  Server publisher accepting connections on port 4041

11:45:55.961 [info]  Server consumer accepting connections on port 4040
```

3. Connect as a consumer:
```
$ telnet 127.0.0.1 4040
Trying 127.0.0.1...
Connected to 127.0.0.1.
Escape character is '^]'.
Please login!
```

4. Trying to subscribe without log in: 

```
$ telnet 127.0.0.1 4040
Trying 127.0.0.1...
Connected to 127.0.0.1.
Escape character is '^]'.
Please login!
  { "type": "SUB",  "topic": "meaw"  }
Please login!
```

5. Log in and subscribing to a topic:
```
log Irina
Succesfully logged in!
{ "type": "SUB",  "topic": "meaw"  }
OK
```

6.Message broker logs:

`11:53:51.662 [info]  Topic "meaw" #PID<0.161.0> is created...`

7. Connecting as publisher:
```
telnet 127.0.0.1 4041
Trying 127.0.0.1...
Connected to 127.0.0.1.
Escape character is '^]'.
```

8. Publishing a message:
```
{ "type": "PUB","topic": "meaw","msg": "Hi there!" } 
```

9. Message broker response:
```
telnet 127.0.0.1 4041
Trying 127.0.0.1...
Connected to 127.0.0.1.
Escape character is '^]'.
{ "type": "PUB","topic": "meaw","msg": "Hi there!" } 
{"msgId":4,"type":"PUBREC"}
```

10. PUBREL :
```
 {"type": "PUBREL", "msgId": 4 } 
```

11. Message broker response:
```
telnet 127.0.0.1 4041
Trying 127.0.0.1...
Connected to 127.0.0.1.
Escape character is '^]'.
{ "type": "PUB","topic": "meaw","msg": "Hi there!" } 
{"msgId":4,"type":"PUBREC"}
 {"type": "PUBREL", "msgId": 4 } 
{"msgId":4,"type":"PUBCOMP"}
```

12. On the consumer telnet connection, the message appeared 5 times, because no PUBREC is send from consumer to message broker. After 5 failures, message broker unsubscribed the consumer, because it did not receive a PUBREC:
```
$ telnet 127.0.0.1 4040
Trying 127.0.0.1...
Connected to 127.0.0.1.
Escape character is '^]'.
Please login!
  { "type": "SUB",  "topic": "meaw"  }
Please login!
log Irina
Succesfully logged in!
{ "type": "SUB",  "topic": "meaw"  }
OK
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
```
13. The consumer has to log in again (if disconnected, but actually here the connection is kept), and subscribe again. Message broker again tries to publish the message:
```
 telnet 127.0.0.1 4040
Trying 127.0.0.1...
Connected to 127.0.0.1.
Escape character is '^]'.
Please login!
  { "type": "SUB",  "topic": "meaw"  }
Please login!
log Irina
Succesfully logged in!
{ "type": "SUB",  "topic": "meaw"  }
OK
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
log
INVALID JSON
log Irina
INVALID JSON
{ "type": "SUB",  "topic": "meaw"  }
OK
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
```

14. Consumer acknowledges the receiving of message with PUBREC:
```
telnet 127.0.0.1 4040
Trying 127.0.0.1...
Connected to 127.0.0.1.
Escape character is '^]'.
Please login!
  { "type": "SUB",  "topic": "meaw"  }
Please login!
log Irina
Succesfully logged in!
{ "type": "SUB",  "topic": "meaw"  }
OK
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
log
INVALID JSON
log Irina
INVALID JSON
{ "type": "SUB",  "topic": "meaw"  }
OK
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{ "type": "PUBREC","msgId": 4, "topic": "meaw" }
OK
```

15. The message broker sends PUBREL:
```
$ telnet 127.0.0.1 4040
Trying 127.0.0.1...
Connected to 127.0.0.1.
Escape character is '^]'.
Please login!
  { "type": "SUB",  "topic": "meaw"  }
Please login!
log Irina
Succesfully logged in!
{ "type": "SUB",  "topic": "meaw"  }
OK
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
log
INVALID JSON
log Irina
INVALID JSON
{ "type": "SUB",  "topic": "meaw"  }
OK
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{ "type": "PUBREC","msgId": 4, "topic": "meaw" }
OK
{"msgId":4,"type":"PUBREL"}
```
16. Consumer sends PUBCOMP, of the same message id:
```
$ telnet 127.0.0.1 4040
Trying 127.0.0.1...
Connected to 127.0.0.1.
Escape character is '^]'.
Please login!
  { "type": "SUB",  "topic": "meaw"  }
Please login!
log Irina
Succesfully logged in!
{ "type": "SUB",  "topic": "meaw"  }
OK
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
log
INVALID JSON
log Irina
INVALID JSON
{ "type": "SUB",  "topic": "meaw"  }
OK
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{"msg":"Hi there!","msgId":4,"topic":"meaw","type":"PUB"}
{ "type": "PUBREC","msgId": 4, "topic": "meaw" }
OK
{"msgId":4,"type":"PUBREL"}
{"type": "PUBCOMP", "msgId": 4,  "topic": "meaw"}
OK
```

17. After consumer sends PUBCOMP, the index of the message is moved, and the next message from the queue can be published by message broker.
In such way, the messages are delivered in the order of arrival and their acknowledgement.

Message broker will retry sending PUBREC to consumer, in the same way it retries to publish the message.
