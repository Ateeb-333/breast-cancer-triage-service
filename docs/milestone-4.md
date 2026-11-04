# Milestone 4
Redis increments a prediction counter on POST /predict when configured.
Redis uses a named data volume and AOF persistence; docker compose down
keeps its volume, while docker compose down -v removes it and resets the count.
Nginx/Redis internal service discovery is through the `redis` Compose hostname.
