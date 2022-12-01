#!/bin/bash

set -o errexit

# image URI (registry/image@sha:*** or ar/registry/image@sha:***)
IMAGE=$1

# check required input parameters
[ -z "$IMAGE" ] && echo "image URI env var not set\n" && exit 1
[ -z "$PROJECT" ] && echo "env var PROJECT env var not set\n" && exit 1
[ -z "$KEY" ] && echo "env var KEY env var not set\n" && exit 1

# parse registry from image 
REGISTRY=$(echo $IMAGE | cut -d'/' -f 1)

# print run variables 
echo "PROJECT:  $PROJECT"
echo "REGISTRY: $REGISTRY"
echo "IMAGE:    $IMAGE"
echo "KEY:      $KEY"
echo "VERSION:  $VERSION" # optional
echo "COMMIT:   $COMMIT"  # optional
echo "SCAN:     $SCAN"  # optional

# confgure gcloud 
gcloud auth configure-docker $REGISTRY --quiet
gcloud config set project $PROJECT

# ensure local public key 
KEY="gcpkms://${KEY}"
cosign generate-key-pair --kms $KEY

# parse optional parameters 
VERSION_ARG=""
if [ -n "${VERSION}" ]
then
      echo "(optional) VERSION not set"
else
      VERSION_ARG="-a version=$VERSION"
fi

COMMIT_ARG=""
if [ -n "${COMMIT}" ]
then
      echo "(optional) COMMIT not set"
else
      COMMIT_ARG="-a commit=$COMMIT"
fi

# sign and verify image 
cosign sign --key $KEY $VERSION_ARG $COMMIT_ARG $IMAGE
cosign verify --key $KEY $IMAGE

# generate SBOM from image and attach it as attestation to the image
syft --scope all-layers -o spdx-json=sbom.spdx.json $IMAGE | jq --compact-output > sbom.spdx.json
cosign attest --predicate sbom.spdx.json --key $KEY $IMAGE

# scan packages in SBOM for vulnerabilities and attach report as attestation to the image
grype --add-cpes-if-none sbom:sbom.spdx.json -o json | jq --compact-output > vulns.grype.json
cosign attest --predicate vulns.grype.json --key $KEY $IMAGE

# verifying all image attestations but skip payload to avoid logging ton of JSON"
cosign verify-attestation --key $(SIGN_KEY) $(IMAGE_SHA) | jq '.payloadType'
