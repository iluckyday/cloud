#!/usr/bin/env bash

file=$1
tag=$2
region=$3
namespace=$4

filename="$(basename $file)"
filepath="$(dirname $file)"

image="$filename:$tag"
cd $filepath
tar -c $filename | docker import - registry.${region}.aliyuncs.com/${namespace}/${image}
docker login -u ${ACR_DOCKER_USERNAME} -p ${ACR_DOCKER_PASSWORD} registry.${region}.aliyuncs.com
docker push registry.${region}.aliyuncs.com/${namespace}/${image}
docker logout registry.${region}.aliyuncs.com
