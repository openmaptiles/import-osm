FROM debian:jessie

RUN DEBIAN_FRONTEND=noninteractive apt-get update \
 # install postgresql client
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      postgresql-client \
      wget \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN wget https://imposm.org/static/rel/imposm3-0.3.0dev-20161216-f4ccff0-linux-x86-64.tar.gz \
  && tar xvzf imposm3-0.3.0dev-20161216-f4ccff0-linux-x86-64.tar.gz \
  && rm imposm3-0.3.0dev-20161216-f4ccff0-linux-x86-64.tar.gz \
  && ln -s /opt/imposm3-0.3.0dev-20161216-f4ccff0-linux-x86-64/imposm3 /usr/bin/imposm3

VOLUME /import /cache /mapping
ENV IMPORT_DIR=/import \
    IMPOSM_CACHE_DIR=/cache \
    MAPPING_YAML=/mapping/mapping.yaml \
    DIFF_DIR=/import \
    TILES_DIR=/import

WORKDIR /usr/src/app
COPY . /usr/src/app/
CMD ["./import_osm.sh"]
