#!/bin/bash -x

cd /workspace

export GO111MODULE=on
export CGO_ENABLED=0
export GOOS=linux
export GOARCH=amd64
export GOCACHE=${PWD}/.gobuild

mkdir -p bin
go build -buildvcs=false -o bin/traxctrl ./cmd/traxctrl
go build -buildvcs=false -o bin/traxcoord ./cmd/traxcoord
