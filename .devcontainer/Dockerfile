# Pull Spark from the official Docker image (much faster than archive.apache.org)
FROM apache/spark:3.5.0 AS spark

FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# -------------------------------------------------------------------
# Match Microsoft Fabric Runtime 1.3
#   Spark 3.5.0 | Java 11 | Scala 2.12.18 | Python 3.11 | R 4.3 | Delta Lake 3.2.0
# -------------------------------------------------------------------

ENV SPARK_HOME=/opt/spark
ENV PATH="${SPARK_HOME}/bin:${SPARK_HOME}/sbin:${PATH}"
ENV PYSPARK_PYTHON=python3

# Install Python 3.11, Java 11, and Spark dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    procps \
    curl \
    jq \
    openjdk-11-jdk-headless \
    software-properties-common \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        python3.11 \
        python3.11-venv \
        python3.11-dev \
        python3.12 \
        python3.12-venv \
        python3.12-dev \
    && rm -rf /var/lib/apt/lists/*

# Set JAVA_HOME (works on both arm64 and amd64)
RUN ln -s /usr/lib/jvm/java-11-openjdk-* /usr/lib/jvm/java-11-openjdk
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk

# Set Python 3.11 as default and install pip
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1 \
    && curl -sS https://bootstrap.pypa.io/get-pip.py | python3.11

# Copy Spark from the official image
COPY --from=spark /opt/spark "${SPARK_HOME}"

# Add MSSQL JDBC driver for SQL Server connectivity via Spark JDBC
RUN curl -L -o "${SPARK_HOME}/jars/mssql-jdbc-12.8.1.jre11.jar" \
    https://repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/12.8.1.jre11/mssql-jdbc-12.8.1.jre11.jar

# Install Azure CLI + GitHub CLI + sqlcmd (mssql-tools18)
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | tee /etc/apt/trusted.gpg.d/microsoft.asc > /dev/null \
    && echo "deb [arch=amd64,arm64] https://packages.microsoft.com/ubuntu/24.04/prod noble main" > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install go-sqlcmd (supports ActiveDirectoryDefault auth)
RUN curl -sL "https://github.com/microsoft/go-sqlcmd/releases/download/v1.9.0/sqlcmd-linux-amd64.tar.bz2" \
    | tar -xj -C /usr/local/bin sqlcmd

# Install PowerShell (the apt package is amd64-only; use tarball on arm64)
ARG PS_VERSION=7.4.6
RUN ARCH="$(dpkg --print-architecture)" \
    && if [ "$ARCH" = "amd64" ]; then \
         apt-get update && apt-get install -y powershell && rm -rf /var/lib/apt/lists/*; \
       else \
         curl -fSL -o /tmp/ps.tar.gz \
           "https://github.com/PowerShell/PowerShell/releases/download/v${PS_VERSION}/powershell-${PS_VERSION}-linux-${ARCH}.tar.gz" \
         && mkdir -p /opt/microsoft/powershell/7 \
         && tar zxf /tmp/ps.tar.gz -C /opt/microsoft/powershell/7 \
         && chmod +x /opt/microsoft/powershell/7/pwsh \
         && ln -s /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh \
         && rm /tmp/ps.tar.gz; \
       fi

# go-sqlcmd is already in /usr/local/bin (on PATH)

# Install uv (fast Python package manager)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Install Python packages (baked into image)
RUN pip install --no-cache-dir \
    pyspark==3.5.0 \
    delta-spark==3.2.0 \
    jupyter \
    pandas==2.1.4 \
    numpy==1.26.4 \
    pyarrow==14.0.2 \
    ms-fabric-cli \
    azure-identity \
    azure-storage-file-datalake \
    ruff \
    pytest \
    pre-commit \
    pytest-cov

# Install pip for Python 3.12
RUN curl -sS https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py \
    && python3.12 /tmp/get-pip.py --break-system-packages \
    && rm /tmp/get-pip.py

# Install Node.js and GitHub Copilot CLI (needed by dev-loop)
# Symlink to /usr/local/bin so it wins over the VS Code copilot-chat shim
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g @github/copilot \
    && ln -sf "$(npm prefix -g)/bin/copilot" /usr/local/bin/copilot
