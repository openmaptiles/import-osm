FROM golang:1.4

RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      libprotobuf-dev \
      libleveldb-dev \
      libgeos-dev \
      libxml2-dev \
      libxslt-dev \
      python-dev \
      postgresql-client \
      osmctools \
      python-pip \
      --no-install-recommends \
 && ln -s /usr/lib/libgeos_c.so /usr/lib/libgeos.so \
 && rm -rf /var/lib/apt/lists/*

WORKDIR $GOPATH/src/github.com/omniscale/imposm3
RUN go get github.com/tools/godep \
 && git clone https://github.com/osm2vectortiles/imposm3 \
        $GOPATH/src/github.com/omniscale/imposm3 \
 && git reset --hard fe896035de33092753e72bc18a61dad5d8050a99 \
 && go get \
 && go install

VOLUME /data/import /data/cache
ENV IMPORT_DATA_DIR=/data/import \
    IMPOSM_CACHE_DIR=/data/cache \
    MAPPING_YAML=/usr/src/app/mapping.yml

WORKDIR /usr/src/app
COPY requirements.txt /usr/src/app/requirements.txt
RUN pip install -r /usr/src/app/requirements.txt
COPY . /usr/src/app/

CMD ["./import-pbf.sh"]
