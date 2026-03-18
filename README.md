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
- `trumpet`
- `tuner`
- `fileserver`
- `plotterfun-node-editor`
- `mongo`

## Requisiti

- Docker
- Docker Compose (`docker-compose`)
- `openssl`

## Configurazione

Creare `.env` nella root del progetto:

```env
DOMAIN=zanotti.iliadboxos.it
MONGO_ROOT_USERNAME=root
MONGO_ROOT_PASSWORD=rootpass
MONGO_DATABASE=app
MONGO_HOST_PORT=27017
MONGO_EXPRESS_HOST_PORT=8081
MONGO_EXPRESS_USERNAME=admin
MONGO_EXPRESS_PASSWORD=adminpass
```

`DOMAIN` viene usato per generare il certificato self-signed.
Le variabili `MONGO_*` configurano il container MongoDB locale.

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

MongoDB:

- container: `mongo`
- volume dati: `./data/mongo`
- host port: `27017` di default
- client web: `mongo-express` su `http://localhost:8081`
- Grafana: `http://localhost:3000`

Nota: su HTTPS il browser mostrerà un avviso perché il certificato è self-signed.

## Monitoraggio

Lo stack include ora:

- `nginx-prometheus-exporter` per le metriche native di `nginx`
- `blackbox-exporter` per sonde HTTP via `nginx`
- `prometheus` per scraping e storage metriche
- `grafana` con dashboard provisionata automaticamente

Porte locali di default:

- Grafana: `http://localhost:3000`

Credenziali Grafana di default:

```env
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=admin
GRAFANA_HOST_PORT=3000
```

Sonde `nginx` disponibili:

- `https://localhost:55443/__monitoring__/ok` restituisce `200`
- `https://localhost:55443/__monitoring__/ko` restituisce `503`
- `https://localhost:55443/__monitoring__/dos` restituisce `429`
- `https://localhost:55443/__monitoring__/rate-limit` usa `limit_req` e restituisce `429` in caso di burst

Metriche `nginx` esposte internamente:

- `http://front-controller:55000/__monitoring__/nginx_status`

La dashboard Grafana mostra:

- richieste e connessioni `nginx`
- stato reachability di tutti gli applicativi pubblicati dietro il reverse proxy
- sonde dedicate `OK`, `KO` e `DOS`
- latenza delle chiamate verso gli applicativi passando da `nginx`

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

## Aggiornare un singolo servizio

Per fermare un servizio, scaricare l'immagine aggiornata e riavviarlo:

```bash
./update-service.sh <service-name>
```

Esempi:

```bash
./update-service.sh crawler
./update-service.sh calendario
./update-service.sh mongo-express
./update-service.sh tuner
./update-service.sh fileserver
```

## Aggiornare tutto lo stack

Per aggiornare tutti i servizi definiti nel compose con un solo comando:

```bash
./updateAll.sh
```

Lo script enumera tutti i servizi del compose e invoca `./update-service.sh` per ciascuno, mostrando alla fine un riepilogo di eventuali errori.

## Monitor TUI locale

Per monitorare lo stato dei servizi del compose da terminale e lanciare l'update del singolo servizio:

```bash
./run-compose-monitor.sh
```

Comandi disponibili nella TUI:

- `Freccia su/giu` oppure `j/k` per cambiare selezione
- `Invio` oppure `u` per eseguire `./update-service.sh <service>`
- `r` per refresh manuale
- `q` per uscire

## MongoDB

MongoDB e disponibile come servizio locale nello stack Docker e salva i dati in:

```text
./data/mongo
```

Credenziali di default:

```env
MONGO_ROOT_USERNAME=root
MONGO_ROOT_PASSWORD=rootpass
MONGO_DATABASE=app
MONGO_HOST_PORT=27017
MONGO_EXPRESS_HOST_PORT=8081
MONGO_EXPRESS_USERNAME=admin
MONGO_EXPRESS_PASSWORD=adminpass
```

Puoi cambiarle in `.env`.

Esempi di accesso:

```text
mongodb://root:rootpass@localhost:27017/admin
http://localhost:8081
```

### Backup

Per creare un backup dentro `./export-mongo/`:

```bash
./mongo-backup.sh
```

Il backup include tutti i database dell'istanza Mongo.

Per specificare un nome custom:

```bash
./mongo-backup.sh my-backup
```

### Restore

Per ripristinare l'ultimo backup disponibile:

```bash
./mongo-restore.sh
```

Il restore ripristina tutti i database contenuti nell'archive selezionato.

Per ripristinare un backup specifico:

```bash
./mongo-restore.sh export-mongo/my-backup.archive.gz
```

### Smoke test backup/restore

Per eseguire un test end-to-end:

```bash
./mongo-smoke-test.sh
```

Lo script:

1. inserisce un documento di test in un database temporaneo
2. esegue il backup completo
3. elimina il database di test
4. esegue il restore dell'archive generato
5. verifica che il documento sia stato ripristinato

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
- `/trumpet/`
- `/tuner/`
- `/fileserver/`
- `/plotterfun-node-editor/`

API `fileserver` pubblicate anche su:

- `/fileserver/api/`

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
