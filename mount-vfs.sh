#!/usr/bin/env bash
set -euo pipefail

SSH_TARGET="${SSH_TARGET:-server}"
MOUNT_DIR="${VFS_MOUNT_DIR:-$HOME/VFS}"
REMOTE_NAME="${VFS_RCLONE_REMOTE:-belle-minio}"
BUCKET="${VFS_BUCKET:-}"
LOCAL_PORT="${VFS_LOCAL_PORT:-19000}"
MINIO_USER="${VFS_MINIO_USER:-rclone-vfs}"
STATE_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}/belle-vfs"
CONTROL_SOCKET="$STATE_DIR/ssh.sock"
LOG_FILE="$STATE_DIR/rclone.log"

usage() {
    cat <<EOF
Uso:
  ./mount-vfs.sh          Monta MinIO in $MOUNT_DIR
  ./mount-vfs.sh unmount  Smonta MinIO e chiude il tunnel SSH
  ./mount-vfs.sh status   Mostra lo stato del mount

Variabili opzionali:
  SSH_TARGET=$SSH_TARGET
  VFS_MOUNT_DIR=$MOUNT_DIR
  VFS_BUCKET=            Vuoto: monta tutti i bucket
                        Esempio: VFS_BUCKET=public-assets
EOF
}

is_mounted() {
    mountpoint -q "$MOUNT_DIR" 2>/dev/null
}

tunnel_is_running() {
    [[ -S "$CONTROL_SOCKET" ]] &&
        ssh -S "$CONTROL_SOCKET" -O check "$SSH_TARGET" >/dev/null 2>&1
}

install_requirements() {
    local missing=()
    command -v rclone >/dev/null 2>&1 || missing+=(rclone)
    command -v fusermount3 >/dev/null 2>&1 || missing+=(fuse3)

    if (( ${#missing[@]} > 0 )); then
        echo "Installazione dipendenze: ${missing[*]}"
        sudo apt-get update
        sudo apt-get install -y "${missing[@]}"
    fi
}

remote_project_dir() {
    ssh "$SSH_TARGET" \
        'docker inspect --format='"'"'{{ index .Config.Labels "com.docker.compose.project.working_dir" }}'"'"' front-controller'
}

configure_rclone() {
    local project_dir quoted_project_dir secret

    if rclone listremotes 2>/dev/null | grep -Fxq "$REMOTE_NAME:"; then
        return
    fi

    echo "Prima configurazione: creo l’utente MinIO dedicato '$MINIO_USER'."
    project_dir="$(remote_project_dir)"
    [[ "$project_dir" == /* && "$project_dir" != *$'\n'* ]] || {
        echo "Directory remota Docker non valida." >&2
        exit 1
    }
    printf -v quoted_project_dir '%q' "$project_dir"
    secret="$(openssl rand -base64 36 | tr -d '\n')"

    printf '%s\n' "$secret" | ssh "$SSH_TARGET" "
        set -eu
        cd $quoted_project_dir
        docker compose run --rm -T --no-deps --entrypoint /bin/sh minio-init -c '
            set -eu
            read -r rclone_secret
            mc alias set local http://minio:9000 \"\$MINIO_ROOT_USER\" \"\$MINIO_ROOT_PASSWORD\" >/dev/null
            mc admin user add local $MINIO_USER \"\$rclone_secret\" >/dev/null
            mc admin policy attach local readwrite --user $MINIO_USER >/dev/null
        '
    "

    rclone config create "$REMOTE_NAME" s3 \
        provider Minio \
        env_auth false \
        access_key_id "$MINIO_USER" \
        secret_access_key "$secret" \
        endpoint "http://127.0.0.1:$LOCAL_PORT" \
        region us-east-1 >/dev/null
    unset secret

    chmod 600 "$(rclone config file | tail -n 1)"
    echo "Configurazione rclone creata."
}

start_tunnel() {
    local minio_ip

    tunnel_is_running && return
    rm -f "$CONTROL_SOCKET"
    minio_ip="$(ssh "$SSH_TARGET" \
        'docker inspect --format='"'"'{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'"'"' vfs-minio')"
    [[ "$minio_ip" =~ ^[0-9a-fA-F:.]+$ ]] || {
        echo "Indirizzo del container MinIO non valido: $minio_ip" >&2
        exit 1
    }

    ssh -M -S "$CONTROL_SOCKET" -fNT \
        -o ExitOnForwardFailure=yes \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -L "127.0.0.1:$LOCAL_PORT:$minio_ip:9000" \
        "$SSH_TARGET"
}

mount_vfs() {
    local remote_path="$REMOTE_NAME:$BUCKET"

    install_requirements
    mkdir -p "$STATE_DIR" "$MOUNT_DIR" "$HOME/.cache/rclone-vfs"
    chmod 700 "$STATE_DIR"

    if is_mounted; then
        echo "VFS già montato in $MOUNT_DIR"
        exit 0
    fi

    configure_rclone
    start_tunnel

    if ! rclone lsd "$remote_path" >/dev/null; then
        echo "Connessione MinIO non riuscita; consulta $LOG_FILE" >&2
        stop_tunnel
        exit 1
    fi

    rclone mount "$remote_path" "$MOUNT_DIR" \
        --vfs-cache-mode writes \
        --cache-dir "$HOME/.cache/rclone-vfs" \
        --vfs-cache-max-size 10G \
        --dir-cache-time 1m \
        --log-file "$LOG_FILE" \
        --log-level INFO \
        --daemon

    echo "VFS montato in $MOUNT_DIR"
    echo "Apri con: nautilus \"$MOUNT_DIR\""
}

stop_tunnel() {
    if tunnel_is_running; then
        ssh -S "$CONTROL_SOCKET" -O exit "$SSH_TARGET" >/dev/null
    fi
    rm -f "$CONTROL_SOCKET"
}

unmount_vfs() {
    if is_mounted; then
        fusermount3 -u "$MOUNT_DIR"
        echo "VFS smontato da $MOUNT_DIR"
    else
        echo "VFS non montato."
    fi
    stop_tunnel
}

show_status() {
    if is_mounted; then
        echo "Mount:  attivo ($MOUNT_DIR)"
    else
        echo "Mount:  non attivo"
    fi
    if tunnel_is_running; then
        echo "Tunnel: attivo (127.0.0.1:$LOCAL_PORT)"
    else
        echo "Tunnel: non attivo"
    fi
    echo "Log:    $LOG_FILE"
}

case "${1:-mount}" in
    mount) mount_vfs ;;
    unmount|umount) unmount_vfs ;;
    status) show_status ;;
    -h|--help|help) usage ;;
    *) usage >&2; exit 2 ;;
esac
