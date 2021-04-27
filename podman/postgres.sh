podman volume create postgres_data

podman run -d -h postgres --name postgres -e POSTGRES_PASSWORD=password -e POSTGRES_INITDB_ARGS=--encoding=UTF-8 -v postgres_data:/var/lib/postgresql/data -p 5432:5432 postgres:12.5
