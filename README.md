# Front Controller

Front controller Docker-based con `nginx` in HTTPS self-signed su:

- `http://localhost:55000`
- `https://localhost:55443`

Espone un punto di ingresso unico verso i servizi interni:

- `app-index`
- `galleria`
- `minicms`
- `watermarks`
- `catalogo-opere`
- `crawler`
- `calendario`

## Requisiti

- Docker
- Docker Compose (`docker-compose`)
- `openssl`

## Configurazione

Creare `.env` nella root del progetto:

```env
DOMAIN=zanotti.iliadboxos.it
```

`DOMAIN` viene usato per generare il certificato self-signed.

## Avvio locale

Per avviare tutto da zero:

```bash
./start.sh
```

Lo script fa queste operazioni:

1. ferma lo stack corrente se esiste
2. genera i certificati self-signed in `certs/live`
3. verifica la presenza di `fullchain.pem` e `privkey.pem`
4. builda senza cache il solo `front-controller`
5. avvia tutto lo stack con `docker-compose`

Endpoint locali:

- `http://localhost:55000`
- `https://localhost:55443`

Nota: su HTTPS il browser mostrerà un avviso perché il certificato è self-signed.

## Avvio in foreground

Per sviluppo o diagnostica:

```bash
./localrun.sh
```

## Stop

Per fermare solo questo progetto:

```bash
./stop.sh
```

Per fermare tutti i container della macchina:

```bash
./stopAll.sh
```

Attenzione: `stopAll.sh` è distruttivo rispetto agli altri stack Docker presenti sull'host.

## Build e publish immagine

Per costruire e pubblicare l'immagine del front controller:

```bash
./deploy.sh
```

Immagine pubblicata:

```text
docker.io/andpra70/front-controller:latest
```

## Avvio con immagini da registry

Per tirare le immagini remote e rialzare lo stack:

```bash
./run.sh
```

## Esempio da server nuovo

Esempio Ubuntu/Debian da macchina pulita.

### 1. Installare Docker

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2 openssl git
sudo systemctl enable --now docker
```

Se `docker-compose-v2` non è disponibile nel repository della distro:

```bash
sudo apt install -y docker-compose-plugin
```

### 2. Clonare il progetto

```bash
git clone <URL-DEL-REPOSITORY> front-controller
cd front-controller
```

### 3. Configurare il dominio

```bash
cat > .env <<'EOF'
DOMAIN=zanotti.iliadboxos.it
EOF
```

### 4. Avviare lo stack

```bash
chmod +x *.sh
./start.sh
```

### 5. Verificare

```bash
docker-compose ps
curl -I http://127.0.0.1:55000
curl -Ik https://127.0.0.1:55443
```

### 6. Esporre dall'esterno

Se il server è dietro router/NAT, inoltrare:

- porta pubblica `80` verso `55000` del server
- porta pubblica `443` verso `55443` del server

Se invece vuoi usare direttamente le porte alte anche dall'esterno:

- `55000 -> 55000`
- `55443 -> 55443`

## Routing applicazioni

Il front controller pubblica questi path:

- `/` homepage statica
- `/app-index/`
- `/catalogo-opere/`
- `/galleria/`
- `/minicms/`
- `/watermarks/`
- `/crawler/`
- `/calendario/`

## Speed test

La homepage include uno speed test browser-side che usa:

- `GET /__speedtest__/download`
- `POST /__speedtest__/upload`

## Troubleshooting

Se il browser mostra errori strani dopo una modifica di configurazione:

```bash
docker-compose down
./start.sh
```

Se `crawler` non riesce a raggiungere Internet, verificare che sia connesso anche alla rete `public-edge`:

```bash
docker-compose ps
docker-compose exec crawler getent hosts www.pinterest.com
```
