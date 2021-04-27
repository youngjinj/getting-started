podman volume create mariadb_data

podman run -d -h mariadb --name mariadb -e MYSQL_ROOT_PASSWORD=password -v mariadb_data:/var/lib/mysql -p 3306:3306 mariadb:10.5 --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
