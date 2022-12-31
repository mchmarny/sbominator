ARG BASE=cgr.dev/chainguard/alpine-base
ARG VERSION=v0.0.1-default

FROM ${BASE}
LABEL sbominator.version="${VERSION}"

# core packages + py for gcloud
RUN echo -e "\nhttp://dl-cdn.alpinelinux.org/alpine/v3.17/community" >> /etc/apk/repositories
RUN apk add --no-cache bash curl docker jq cosign ca-certificates python3 

# gcloud
ENV CLOUDSDK_INSTALL_DIR /gcloud/
RUN curl -sSL https://sdk.cloud.google.com | bash
ENV PATH $PATH:/gcloud/google-cloud-sdk/bin/
RUN gcloud components install beta --quiet 

# anchore tool
RUN curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin

# sbominator
COPY builder /usr/local/bin
ENTRYPOINT ["/usr/local/bin/builder"]
