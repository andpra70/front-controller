# Front Controller

Front controller Docker-based con:

- un solo `nginx` pubblico sulle porte `80` e `443`
- certificato Let's Encrypt richiesto e rinnovato automaticamente da Certbot
- log effimeri nel container, ruotati giornalmente e conservati per 7 giorni

Espone un punto di ingresso unico verso i servizi interni:

- `galleria`
- `minicms`
- `watermarks`
- `catalogo-opere`
- `crawler`
- `calendario`
- `ginnastica`
- `trumpet`
- `tuner`
- `fileserver`
- `plotterfun-node-editor`
- `mongo`

## Requisiti

- Docker
- Docker Compose (`docker-compose`)

## Configurazione

Creare `.env` nella root del progetto:

```env
DOMAIN=zanotti.iliadboxos.it
LETSENCRYPT_EMAIL=nome@example.com
```

`DOMAIN` viene usato per HTTPS, OAuth e CORS. Certbot salva certificati e stato
in `./letsencrypt`; il front-controller rileva automaticamente emissioni e
rinnovi tramite un volume certificati dedicato e ricarica Nginx.
`LETSENCRYPT_EMAIL` riceve gli avvisi di Let's Encrypt.
Le variabili OAuth non sono piu gestite dal `.env` root: `oauth-server` usa il suo `.env` interno.

Variabili opzionali che puoi aggiungere al `.env` root:

```env
MONGO_ROOT_USERNAME=root
MONGO_ROOT_PASSWORD=rootpass
MONGO_DATABASE=app
MONGO_HOST_PORT=27017
MONGO_EXPRESS_HOST_PORT=8081
MONGO_EXPRESS_USERNAME=admin
MONGO_EXPRESS_PASSWORD=adminpass
```

## Avvio locale

Per avviare tutto da zero:

```bash
./start.sh
```

Lo script fa queste operazioni:

1. ferma lo stack corrente se esiste
2. builda senza cache il `front-controller`
3. avvia lo stack, incluso Certbot

Endpoint locali:

- `http://<DOMAIN>` (redirect a HTTPS)
- `https://<DOMAIN>`

MongoDB:

- container: `mongo`
- volume dati: `./data/mongo`
- host port: `27017` di default
- client web: `mongo-express` su `http://localhost:8081`

## Configurare HTTPS con Let's Encrypt

Prima dell'avvio, il record DNS A/AAAA di `DOMAIN` deve puntare all'IP pubblico
del server. Se il server è dietro NAT, inoltrare TCP `80` e `443` alle stesse
porte del server Docker. La porta `80` è necessaria anche per la challenge HTTP
di Let's Encrypt.

Avviare lo stack con `./start.sh`. Nginx parte immediatamente con un certificato
temporaneo valido un giorno; Certbot esegue la challenge HTTP, installa il
certificato pubblico e Nginx lo carica automaticamente entro 60 secondi.

Non usare `localhost` per richiedere un certificato pubblico.

### Dove si trova il certificato

Certbot conserva lo stato persistente nella directory del progetto:

```text
./letsencrypt/
```

Per il dominio configurato, i riferimenti principali sull'host sono:

```text
./letsencrypt/live/<DOMAIN>/fullchain.pem
./letsencrypt/live/<DOMAIN>/privkey.pem
```

Con `DOMAIN=belle.iliadboxos.it` diventano:

```text
./letsencrypt/live/belle.iliadboxos.it/fullchain.pem
./letsencrypt/live/belle.iliadboxos.it/privkey.pem
```

Questi file sono link gestiti da Certbot verso le versioni numerate presenti
in `./letsencrypt/archive/<DOMAIN>/`. La configurazione del rinnovo si trova in
`./letsencrypt/renewal/<DOMAIN>.conf`. Le directory e la chiave privata sono
intenzionalmente accessibili solo a `root`: non modificarne proprietario o
permessi e non aggiungere `./letsencrypt` al repository Git.

Per mantenere Nginx non-root, Certbot pubblica inoltre una copia runtime nel
volume Docker `front-controller_nginx-certs`, montato nei container come:

```text
/etc/nginx-certs/fullchain.pem
/etc/nginx-certs/privkey.pem
```

Nginx copia questi file nella propria directory effimera
`/tmp/front-controller-tls` e ricarica la configurazione quando il certificato
cambia. La fonte da salvare nei backup è sempre `./letsencrypt`, non il volume
runtime.

Per controllare il certificato attualmente pubblicato:

```bash
openssl s_client -connect "${DOMAIN}:443" -servername "${DOMAIN}" </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

Certbot controlla il rinnovo ogni 12 ore. Dopo un rinnovo, Nginx carica il nuovo
certificato entro 60 secondi.

## Log Nginx

I file `front-controller-access.log` ed `error.log` restano nel filesystem
effimero del container. Sono ruotati ogni giorno, compressi e conservati per
7 rotazioni. Vengono eliminati quando il container viene rimosso.

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

Il riquadro del servizio selezionato mostra stato runtime, processi `top`, RAM, uso disco del container e live tail log.

Comandi disponibili nella TUI:

- `Freccia su/giu` oppure `j/k` per cambiare selezione
- `Invio` oppure `u` per eseguire `./update-service.sh <service>`
- `l` per attivare o disattivare il live tail delle ultime 5 righe di log del servizio selezionato
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
sudo apt install -y docker.io docker-compose-v2 git
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
LETSENCRYPT_EMAIL=nome@example.com
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
curl -I http://zanotti.iliadboxos.it
curl -I https://zanotti.iliadboxos.it
```

### 6. Esporre dall'esterno

Se il server è dietro router/NAT, inoltrare:

- porta pubblica `80` verso `80` del server
- porta pubblica `443` verso `443` del server


## Routing applicazioni

Il front controller pubblica questi path:

- `/` homepage statica
- `/catalogo-opere/`
- `/galleria/`
- `/minicms/`
- `/watermarks/`
- `/crawler/`
- `/calendario/`
- `/ginnastica/`
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

Per verificare Certbot e forzare un nuovo tentativo dopo aver corretto DNS o NAT:

```bash
docker-compose restart certbot
docker-compose logs -f certbot
```

Per verificare che il front-controller sia healthy:

```bash
docker-compose ps front-controller certbot
curl -I "https://${DOMAIN}/"
```

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
