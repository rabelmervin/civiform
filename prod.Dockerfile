# syntax=docker/dockerfile:1@sha256:4c68376a702446fc3c79af22de146a148bc3367e73c25a5803d453b6b3f722fb
# For production images, use the adoptium.net official JRE & JDK docker images.
FROM --platform=linux/amd64 eclipse-temurin:17.0.14_7-jdk-alpine@sha256:b16e661d76d3af0d226d0585063dbcafe7fb8a4ef31cfcaaec71d39c41269420 AS stage1

ARG SBT_VERSION
ENV SBT_VERSION="${SBT_VERSION}"
ENV INSTALL_DIR=/usr/local
ENV SBT_HOME=/usr/local/sbt
ENV PATH="${PATH}:${SBT_HOME}/bin"
ENV SBT_URL="https://github.com/sbt/sbt/releases/download/v$SBT_VERSION/sbt-$SBT_VERSION.tgz"

RUN set -o pipefail && \
    apk update && \
    apk add --upgrade apk-tools && \
    apk upgrade --available && \
    apk add --no-cache --update bash wget npm git && \
    mkdir -p "$SBT_HOME" && \
    wget -qO - "${SBT_URL}" | tar xz -C "${INSTALL_DIR}" && \
    echo -ne "- with sbt $SBT_VERSION\n" >> /root/.built

ENV PROJECT_HOME=/usr/src
ENV PROJECT_NAME=server
ENV PROJECT_LOC="${PROJECT_HOME}/${PROJECT_NAME}"

COPY "${PROJECT_NAME}" "${PROJECT_LOC}"
RUN cd "${PROJECT_LOC}" && \
    npm install -g npm && \
    npm install && \
    sbt addCustomAssets && \
    sbt update && \
    sbt dist && \
    unzip "${PROJECT_LOC}/target/universal/civiform-server-0.0.1.zip" -d / && \
    chmod +x /civiform-server-0.0.1/bin/civiform-server

# This is a common trick to shrink container sizes. We discard everything added
# during the build phase and use only the inflated artifacts created by sbt dist.
FROM --platform=linux/amd64 eclipse-temurin:17.0.14_7-jre-alpine@sha256:865cca6d0b31f284a5fc4e8cbd8f9375f470fd07cf6e909cea62f2790d4187fe AS stage2
COPY --from=stage1 /civiform-server-0.0.1 /civiform-server-0.0.1

# Upgrade packages for stage2 to include latest versions.
RUN set -o pipefail && \
    apk update && \
    apk add --upgrade apk-tools && \
    apk upgrade --available && \
    apk add --no-cache --update bash openssh

ARG image_tag
ENV CIVIFORM_IMAGE_TAG=$image_tag

ARG git_commit_sha
LABEL civiform.git.commit_sha=$git_commit_sha

CMD ["/civiform-server-0.0.1/bin/civiform-server", "-Dconfig.file=/civiform-server-0.0.1/conf/application.conf"]
