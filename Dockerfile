ARG IMAGE=irishealth-aihub:2026.3.0AI.154.0
FROM ${IMAGE} AS iris

# .NET 8 build of the PEX operation Hl7Check (NHapi), against the IRIS .NET SDK of this image
# (pex/integration/Dockerfile.hl7check.fragment; NuGet restore needs network at build time).
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS hl7build
COPY --from=iris /usr/irissys/dev/dotnet/bin/net8.0/ /irissdk/
COPY pex/dotnet/Hl7Check/ /src-hl7/
RUN dotnet publish /src-hl7/Hl7Check.csproj -c Release -o /out-hl7 -p:IrisSdk=/irissdk \
 && rm -rf /out-hl7/runtimes /out-hl7/*.pdb

FROM mcr.microsoft.com/dotnet/runtime:8.0 AS dotnetrt

FROM iris

WORKDIR /home/irisowner/dev

ARG NAMESPACE="IRISAPP"

ENV IRISUSERNAME "_SYSTEM"
ENV IRISPASSWORD "SYS"
ENV IRISNAMESPACE $NAMESPACE
ENV PYTHON_PATH=/usr/irissys/bin/
ENV PYTHONPATH="/usr/irissys/lib/python"
ENV PATH "/usr/irissys/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/irisowner/bin"

# .NET 8 runtime for the %DotNet Server gateway + the published Hl7Check DLLs (PexHl7Check classpaths)
USER root
COPY --from=dotnetrt /usr/share/dotnet /usr/share/dotnet
RUN ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
USER irisowner
ENV DOTNET_ROOT=/usr/share/dotnet \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
COPY --from=hl7build --chown=irisowner:irisowner /out-hl7/ /home/irisowner/pex/hl7check/

COPY merge.cpf /home/irisowner/dev/merge.cpf

RUN --mount=type=bind,src=.,dst=. \
    iris start IRIS && \
    iris merge IRIS /home/irisowner/dev/merge.cpf && \
    iris session IRIS < iris.script && \
    iris stop IRIS quietly
