FROM bitwalker/alpine-elixir:latest as build
 
ENV MIX_ENV=prod

EXPOSE 4040
EXPOSE 4041

WORKDIR /app

COPY . .

RUN mix deps.get

# RUN apt-get update && apt-get install -y erlang-observer

RUN mix escript.build


CMD "/app/message_broker"
