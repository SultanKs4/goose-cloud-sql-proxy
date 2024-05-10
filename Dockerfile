FROM gcr.io/cloudsql-docker/gce-proxy as cloudsql-proxy

FROM golang:1.22-alpine as base

# for alpine base image we need to install bash
RUN apk add --no-cache --upgrade bash

WORKDIR /migrator

# copy the cloud_sql_proxy binary from the cloudsql-proxy image to the base image
COPY --from=cloudsql-proxy ./cloud_sql_proxy cloud_sql_proxy

# install goose
RUN go install github.com/pressly/goose/v3/cmd/goose@latest

# copy the scripts to the base image
COPY ./scripts scripts

ENTRYPOINT ["scripts/entrypoint.sh"]