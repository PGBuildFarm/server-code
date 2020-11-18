#!/bin/sh

# script to select sample data suitable for populating a test instance

# the large tables are sampled, the small tables are complete,
# all secret and personal info is removed from buildsystems

DIR=`mktemp -d`
cd $DIR

psql -q pgbfprod <<'EOF'

set client_encoding = 'UTF8';
\copy (select * from build_status_log_raw x where sysname in ('prion','drongo') and branch = 'HEAD' and exists (select 1 from dashboard_mat d where d.sysname = x.sysname and d.snapshot = x.snapshot)) to build_status_log_raw.data
\copy (select * from build_status_raw x where exists (select 1 from dashboard_mat d where d.sysname = x.sysname and d.snapshot = x.snapshot)) to build_status_raw.data
\copy (select * from build_status_recent_500 where report_time > now() - interval '90 days') to build_status_recent_500.data
\copy (select name,name,operating_system,os_version,compiler,compiler_version,architecture,status,'foo'::text,'foo@bar.baz'::text,status_ts,no_alerts,sys_notes,sys_notes_ts from public.buildsystems) to buildsystems.data
\copy alerts to alerts.data
\copy dashboard_last_modified to dashboard_last_modified.data
\copy dashboard_mat to dashboard_mat.data
\copy latest_snapshot to latest_snapshot.data
\copy nrecent_failures to nrecent_failures.data
\copy personality to personality.data
\copy partman.part_config to partman_part_config.data

EOF

cat > load-sample-data.sql <<EOF

begin;
set client_encoding = 'UTF8';
alter table build_status_raw disable trigger user;
\copy buildsystems from buildsystems.data
\copy alerts from alerts.data
\copy build_status_raw from build_status_raw.data
\copy build_status_log_raw from build_status_log_raw.data
\copy build_status_recent_500 from build_status_recent_500.data
\copy dashboard_last_modified from dashboard_last_modified.data
\copy dashboard_mat from dashboard_mat.data
\copy latest_snapshot from latest_snapshot.data
\copy nrecent_failures from nrecent_failures.data
\copy personality from personality.data
\copy partman.part_config from partman_part_config.data
alter table build_status_raw enable trigger user;
commit;

EOF

cat > unload-sample-data.sql <<EOF

begin;
set client_encoding = 'UTF8';
alter table build_status_raw disable trigger user;
truncate buildsystems
 ,  alerts
 ,  build_status_raw
 ,  build_status_log_raw
 ,  build_status_recent_500
 ,  dashboard_last_modified
 ,  dashboard_mat
 ,  latest_snapshot
 ,  nrecent_failures
 ,  personality
 ,  partman.part_config;
alter table build_status_raw enable trigger user;
commit;

EOF

tar -z -cf sample-data.tgz *.data *load-sample-data.sql && mv sample-data.tgz /home/pgbuildfarm/website/htdocs/downloads

cd

rm -rf $DIR


