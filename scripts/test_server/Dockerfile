# The PostgreSQL test server image for every cookbook recipe.
#
# The pgEdge Postgres image already carries pgvector, Snowflake, the pgEdge
# Vectorizer and pg_stat_statements. pg_semantic_cache is not packaged
# anywhere, so this image builds it from a pinned commit of its source.
#
# scripts/start_test_server.sh builds this image when it is missing and
# tags it with a hash of this file, so any edit here gives a new tag.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

FROM ghcr.io/pgedge/pgedge-postgres:18.6-spock5.0.13-standard-2

# pg_semantic_cache 0.1.0-beta4. The checksum is of GitHub's archive of
# this commit; update both together.
ARG SEMANTIC_CACHE_COMMIT=f946dff6183984dd0eebc962031eb66d6668c014
ADD --checksum=sha256:6f33aa9cd46b22ee216979d48c96b777697e32fba57441bffae002035b7cd611 \
    https://github.com/pgEdge/pg_semantic_cache/archive/${SEMANTIC_CACHE_COMMIT}.tar.gz \
    /tmp/pg_semantic_cache.tar.gz

USER root

# Install the toolchain, build and install the extension, then remove the
# toolchain again in the same layer so that it adds nothing to the image.
# The server was configured --with-llvm, so PGXS would also compile LLVM
# bitcode with clang; with_llvm=no skips that, and the extension still
# runs (it is simply not inlined by the JIT compiler). PGXS reuses the
# server's CFLAGS, which name Red Hat's compiler spec files, so the build
# also needs redhat-rpm-config.
RUN set -eux; \
    dnf install -y gcc make redhat-rpm-config pgedge-postgresql18-devel; \
    mkdir /tmp/pg_semantic_cache; \
    tar -xzf /tmp/pg_semantic_cache.tar.gz --strip-components=1 \
        -C /tmp/pg_semantic_cache; \
    make -C /tmp/pg_semantic_cache with_llvm=no; \
    make -C /tmp/pg_semantic_cache with_llvm=no install; \
    dnf remove -y gcc make redhat-rpm-config pgedge-postgresql18-devel; \
    dnf clean all; \
    rm -rf /tmp/pg_semantic_cache /tmp/pg_semantic_cache.tar.gz \
        /var/cache/dnf

USER postgres

# The pgEdge image sets no locale, so initdb would create a SQL_ASCII
# cluster with the C locale, and drivers such as psycopg then return text
# as bytes. Use the same locale as the official postgres image, which gives
# UTF8 and en_US.utf8 collation.
ENV LANG=en_US.utf8
