FROM alpine

# core packages + py for gcloud
RUN apk add --no-cache bash curl docker jq cosign ca-certificates python3 

# gcloud
RUN mkdir -p /builder && \
    wget -qO- https://dl.google.com/dl/cloudsdk/release/google-cloud-sdk.tar.gz | tar zxv -C /builder && \
    /builder/google-cloud-sdk/install.sh --usage-reporting=false \
        --bash-completion=false \
        --disable-installation-options

# add gcloud to path 
ENV PATH=/builder/google-cloud-sdk/bin/:$PATH

# anchore tools 
RUN curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
RUN curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin

# crane
RUN curl -L -o crane https://github.com/michaelsauter/crane/releases/download/v3.6.1/crane_linux_amd64 && chmod +x crane && mv crane /usr/local/bin/crane


COPY builder /usr/local/bin
ENTRYPOINT ["/usr/local/bin/builder"]