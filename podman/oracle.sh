podman volume create oracle_data

podman run -d -h oracle --name oracle -e ORACLE_PWD=password -v oracle_data:/opt/oracle/oradata -p 1521:1521 -p 5500:5500 oracle/database:19.3.0-ee
