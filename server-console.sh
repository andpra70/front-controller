#!/usr/bin/env bash
set -euo pipefail

SSH_TARGET="${SSH_TARGET:-server}"

usage() {
    cat <<'EOF'
Uso:
  ./server-console.sh logs                 Segue accessi ed errori Nginx
  ./server-console.sh logs SERVIZIO...     Segue i log Docker dei servizi indicati
  ./server-console.sh vfs                  Apre una shell mc per navigare MinIO

Variabili:
  SSH_TARGET=server                        Host o alias SSH (default: server)

Nella shell MinIO:
  mc tree local                            Mostra bucket e directory
  mc ls local/public-assets                Elenca il VFS privato
  mc ls local/published-assets             Elenca gli oggetti pubblicati
  mc find local/public-assets              Elenca ricorsivamente gli oggetti
  mc stat local/public-assets/PERCORSO      Mostra metadata e dimensione
  exit                                     Chiude la sessione
EOF
}

remote_project_command() {
    local command="$1"

    ssh -t "$SSH_TARGET" "
        set -eu
        project_dir=\$(docker inspect \
            --format='{{ index .Config.Labels \"com.docker.compose.project.working_dir\" }}' \
            front-controller)
        if [ -z \"\$project_dir\" ] || [ ! -d \"\$project_dir\" ]; then
            echo \"Impossibile individuare la directory del progetto Docker.\" >&2
            exit 1
        fi
        cd \"\$project_dir\"
        $command
    "
}

follow_nginx_logs() {
    exec ssh -t "$SSH_TARGET" \
        docker exec front-controller tail -n 100 -F \
        /var/log/nginx/front-controller-access.log \
        /var/log/nginx/error.log
}

follow_service_logs() {
    local services=()
    local service

    for service in "$@"; do
        [[ "$service" =~ ^[a-zA-Z0-9_-]+$ ]] || {
            echo "Nome servizio non valido: $service" >&2
            exit 2
        }
        services+=("$service")
    done

    remote_project_command "docker compose logs --tail 100 -f ${services[*]}"
}

browse_vfs() {
    echo "Apro la shell MinIO sul server. Digita 'mc tree local' per iniziare."
    remote_project_command \
        "docker compose run --rm --no-deps --entrypoint /bin/sh minio-init -c '
            set -eu
            mc alias set local http://minio:9000 \"\$MINIO_ROOT_USER\" \"\$MINIO_ROOT_PASSWORD\" >/dev/null
            echo \"Connessione MinIO pronta. Bucket disponibili:\"
            mc ls local
            exec /bin/sh
        '"
}

choose_action() {
    printf '%s\n' \
        "1) Segui accessi/errori Nginx" \
        "2) Segui tutti i log applicativi" \
        "3) Naviga VFS MinIO" \
        "q) Esci"
    read -r -p "> " choice

    case "$choice" in
        1) follow_nginx_logs ;;
        2) follow_service_logs ;;
        3) browse_vfs ;;
        q|Q) exit 0 ;;
        *) echo "Scelta non valida." >&2; exit 2 ;;
    esac
}

case "${1:-}" in
    "")
        choose_action
        ;;
    logs)
        shift
        if (( $# == 0 )); then
            follow_nginx_logs
        else
            follow_service_logs "$@"
        fi
        ;;
    vfs)
        shift
        (( $# == 0 )) || { usage >&2; exit 2; }
        browse_vfs
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
