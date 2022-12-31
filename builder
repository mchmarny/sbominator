#!/bin/bash

set -o errexit

# image URI (registry/image@sha:*** or ar/registry/image@sha:***)
IMAGE=$1

# check required input parameters
[ -z "$IMAGE" ] && echo "image URI env var not set" && exit 1
[ -z "$PROJECT" ] && echo "env var PROJECT env var not set" && exit 1
[ -z "$KEY" ] && echo "env var KEY env var not set" && exit 1
[ -z "$VERSION" ] && echo "env var VERSION env var not set" && exit 1
[ -z "$COMMIT" ] && echo "env var COMMIT env var not set" && exit 1

# parse registry from image 
REGISTRY=$(echo $IMAGE | cut -d'/' -f 1)

# print run variables 
echo "PROJECT:  $PROJECT"
echo "REGISTRY: $REGISTRY"
echo "IMAGE:    $IMAGE"
echo "KEY:      $KEY"
echo "ATTESTOR: $ATTESTOR"
echo "VERSION:  $VERSION"
echo "COMMIT:   $COMMIT"

# confgure gcloud 
gcloud auth configure-docker $REGISTRY --quiet
gcloud config set project $PROJECT

# ensure local public key 
CO_KEY="gcpkms://${KEY}"

if [ ! -f cosign.pub ]; then
    echo "Generate public key-pair from KMS..."
    cosign generate-key-pair --kms $CO_KEY
fi

echo "Signing image..."
cosign sign --key $CO_KEY -a "version=${VERSION}" -a "commit=${COMMIT}" $IMAGE

echo "Generate SBOM..."
syft --quiet -o spdx-json=sbom.spdx.json $IMAGE | jq --compact-output > sbom.spdx.json

echo "Adding SBOM attestation..."
cosign attest --predicate sbom.spdx.json --type spdxjson --key $CO_KEY $IMAGE

echo "Verifying image SPDX attestation..."
cosign verify-attestation --type spdxjson --key $CO_KEY $IMAGE | jq '.payloadType'

# attest the image with GCP Binary Authorization
if [ ! -z "$ATTESTOR" ]
then
    echo "Adding binauthz attestation..."
    gcloud beta container binauthz attestations sign-and-create \
        --attestor $ATTESTOR \
        --artifact-url $IMAGE \
        --keyversion $KEY
fi
