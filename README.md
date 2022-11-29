# Cloud Build SBOM builder

This builder is designed to be used in Google Cloud Build pipeline. It crates a Software Bill of Materials (SBOM) from a previously built image in GCP Artifact Registry. When executed in your pipeline, it will:

* Sign and verify provided image based on its digest
* Publish image signature to the registry
* Generate SBOM file for all image layers in JSON format ([SPDX schema ](https://github.com/spdx/spdx-spec/blob/v2.2/schemas/spdx-schema.json))
* Create SBOM attestation and publish it to registry

> Optionally, this builder can be configured to generate vulnerability report based on the SBOM. 

![](images/reg.png)

## Usage

When signing images it's best to do it based on image digest, not image tag. When publishing the image to GCP Artifact Registry, you should also extracted the digest of the newly published image. To enable other steps in the pipeline to access that digest, write it to a temporary file like this:

```shell
docker image inspect $IMAGE_TAG --format '{{index .RepoDigests 0}}' > image-digest.txt
```

To add the SBOM generation step to your pipeline, add the following step to your pipeline, anywhere after the image is published and the digest is written to file:

```yaml
- id: sbom
  name: us-docker.pkg.dev/cloudy-demos/builders/sbom-builder:v0.3.4
  entrypoint: /bin/bash
  env:
  - PROJECT=$PROJECT_ID
  - KEY=$_KMS_KEY_NAME
  args:
  - -c
  - |
    builder $(/bin/cat image-digest.txt)
```

Optionally, you can also add image tag (`COMMIT`) and commit sha (`VERSION`) during image signing. The built-in variables are always available for tag-triggered pipelines: 

```yaml
  - COMMIT=$COMMIT_SHA # optional
  - VERSION=$TAG_NAME  # optional
```

Additionally, the builder can also generate vulnerability report from the SBOM, and upload the signed report to registry. To enable that option, set the `SCAN` variable to any non-empty string: 

```yaml
  - SCAN=yes
```

A complete pipeline with all the steps in below image is available in the [example folder](example/cloudbuild.yaml).

![](images/build.png)

## Assumptions 
 
* Cloud KMS key and Cloud Build service account permissions enabled for Cloud KMS in [Cloud Build settings](https://console.cloud.google.com/cloud-build/settings/service-account) (disabled by defaults)

## Technology 

This builder uses following open source projects:

* [cosign](https://github.com/sigstore/cosign) for signing
* [syft](https://github.com/anchore/syft) for SBOM generation 
* [grype](https://github.com/anchore/grype) for vulnerability scans 
* [crane](https://github.com/michaelsauter/crane) for registry queries 
* [alpine](https://github.com/alpinelinux) Linux as base image

Additionally, this builder users Google Cloud CLI ([gcloud](https://cloud.google.com/sdk/gcloud)) for environment configuration.

## Disclaimer

This is my personal project and it does not represent my employer. While I do my best to ensure that everything works, I take no responsibility for issues caused by this code.