# k3s image: the compose image (built from ../../Dockerfile) + the repo baked into /irisdev/app,
# flattened to one layer. The IRIS build step copies whole library DBs (hslib 1.6 GB) into a new
# layer, so flattening drops ~3 GB of duplicates.
# Build from the repo root (see deploy/k8s/README.md):
#   docker build --platform linux/amd64 -f deploy/k8s/Dockerfile --build-arg APP=interop-ops-agent-iris:amd64 -t ioa-k8s:<tag> .
ARG APP=interop-ops-agent-iris:amd64
FROM ${APP} AS app
USER root
# Paths in Production.cls and Setup.cls are /irisdev/app/... (compose bind-mounts the repo there).
COPY --chown=irisowner:irisowner . /irisdev/app

FROM scratch
COPY --from=app / /
ENV ISC_PACKAGE_IRISGROUP=irisowner ISC_PACKAGE_IRISUSER=irisowner \
    ISC_PACKAGE_MGRGROUP=irisowner ISC_PACKAGE_MGRUSER=irisowner \
    IRISSYS=/home/irisowner/irissys ISC_PACKAGE_INSTANCENAME=IRIS ISC_PACKAGE_INSTALLDIR=/usr/irissys \
    PATH=/usr/irissys/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/irisowner/bin \
    PYTHONPATH=/usr/irissys/lib/python PYTHON_PATH=/usr/irissys/bin/ \
    LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    IRISNAMESPACE=IRISAPP \
    DOTNET_ROOT=/usr/share/dotnet DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
USER irisowner
WORKDIR /home/irisowner/dev
EXPOSE 52773
ENTRYPOINT ["/tini", "--", "/iris-main"]
