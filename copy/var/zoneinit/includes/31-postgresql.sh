IP_INTERNAL=$(mdata-get sdc:nics | /usr/bin/json -ag ip -c 'this.nic_tag === "admin"' 2>/dev/null);

# Get password from metadata, unless passed as PGSQL_PW, or set one.
log "getting pgsql password from mdata-get"
PGSQL_PW=${PGSQL_PW:-$(mdata-get psql_postgres_pwd 2>/dev/null)} || \
PGSQL_PW=$(od -An -N8 -x /dev/random | head -1 | tr -d ' ');

echo "${PGSQL_PW}" > /var/tmp/pgpasswd

[[ -d "/var/pgsql/data" ]] && rm -rf /var/pgsql/data

log "initializing PostgreSQL"
su - postgres -c "/opt/local/bin/initdb \
                  --pgdata=/var/pgsql/data \
                  --encoding=UTF8 \
                  --locale=en_US.UTF-8 \
                  --auth=password \
                  --pwfile=/var/tmp/pgpasswd" >/dev/null || \
  (log "PostgreSQL init command failed" && exit 31);

rm /var/tmp/pgpasswd

log "tuning postgresql"
SHARED_BUFFERS="$(( (${RAM_IN_BYTES} / 4) / 1024/1024 ))MB";
EFFECTIVE_CACHE_SIZE="$(( (${RAM_IN_BYTES} / 4) / 1024/1024 ))MB";
[[ ${RAM_IN_BYTES} -ge "4294967296" ]] && CHECKPOINT_SEGMENTS="24" || CHECKPOINT_SEGMENTS="12";
[[ ${RAM_IN_BYTES} -ge "4294967296" ]] && MAX_CONNECTIONS="1000" || MAX_CONNECTIONS="500";
[[ ${RAM_IN_BYTES} -ge "4294967296" ]] && MAINTENANCE_WORK_MEM="64MB" || MAINTENANCE_WORK_MEM="16MB"

gsed -i "/^shared_buffers/s/shared_buffers.*/shared_buffers = ${SHARED_BUFFERS}/" /var/pgsql/data/postgresql.conf
gsed -i "/^#effective_cache_size/s/#effective_cache_size.*/effective_cache_size = ${EFFECTIVE_CACHE_SIZE}/" /var/pgsql/data/postgresql.conf
gsed -i "/^#checkpoint_segments/s/#checkpoint_segments.*/checkpoint_segments = ${CHECKPOINT_SEGMENTS}/" /var/pgsql/data/postgresql.conf
gsed -i "/^max_connections/s/max_connections.*/max_connections = ${MAX_CONNECTIONS}/" /var/pgsql/data/postgresql.conf
gsed -i "/^#work_mem/s/#work_mem.*/work_mem = 1MB/" /var/pgsql/data/postgresql.conf
gsed -i "/^#maintenance_work_mem/s/#maintenance_work_mem.*/maintenance_work_mem = ${MAINTENANCE_WORK_MEM}/" /var/pgsql/data/postgresql.conf
gsed -i "/^#listen_addresses/s/#listen_addresses.*/listen_addresses = '${IP_INTERNAL}'/" /var/pgsql/data/postgresql.conf

gsed -i \
  "s/local   all             all                                     password/#local   all             all                                     password/" \
  /var/pgsql/data/pg_hba.conf

echo "host    all             all             ${IP_INTERNAL}/32         password" >> /var/pgsql/data/pg_hba.conf
echo "local   all             postgres                                peer" >> /var/pgsql/data/pg_hba.conf

log "starting PostgreSQL"
svcadm enable -s postgresql
