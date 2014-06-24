#!/bin/sh

VERSION=3.3.3

echo "Fetching rabbitmq"

mkdir -p deps

curl http://www.rabbitmq.com/releases/rabbitmq-erlang-client/v${VERSION}/amqp_client-${VERSION}.ez -o deps/amqp_client-${VERSION}.ez
curl http://www.rabbitmq.com/releases/rabbitmq-erlang-client/v${VERSION}/rabbit_common-${VERSION}.ez -o deps/rabbit_common-${VERSION}.ez

cd deps

unzip amqp_client-${VERSION}.ez
unzip rabbit_common-${VERSION}.ez

rm -rf amqp_client rabbit_common

mv amqp_client-${VERSION} amqp_client
mv rabbit_common-${VERSION} rabbit_common

rm *.ez

cd ..
