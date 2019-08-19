#!/bin/bash
set -eo pipefail

#########################################
# add vars
CERT_PATH="./../certbot"
NGINX_PATH="./../config/nginx"
NGINX_TEMPLATE_PATH="./../config/nginx/app.tmpl"
DOCKER_FILE="./../services/docker-compose.yml"
rsa_key_size=4096

#########################################
# load input vars
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -h|--host)
    APP_HOST="$2"
    shift # past argument
    shift # past value
    ;;
    -p|--port)
    APP_PORT="$2"
    shift # past argument
    shift # past value
    ;;
    -s|--service)
    APP_SERVICE="$2"
    shift # past argument
    shift # past value
    ;;
    -e|--email)
    USER_EMAIL="$2"
    shift # past argument
    shift # past value
    ;;
    --staging)
    STAGING=1
    shift # past argument
    ;;
    -d|--domains)
    DOMAINS="$2"
    shift # past argument
    shift # past value
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

#########################################
# add warn messages
succ ()  { echo -e "  " - $(tput bold)$(tput setaf 2) $@ $(tput sgr 0) ; }
info ()  { echo -e "  " /-- $(tput bold)$(tput setaf 4) $@ $(tput sgr 0) ; }
warn ()  { echo -e !-- $(tput bold)$(tput setaf 3) $@ $(tput sgr 0) ; }
error () { echo -e !!! $(tput bold)$(tput setaf 1) $@ $(tput sgr 0) ; }

#########################################
# create functions
create_dummy_certs() {
  # variables
  warn "Creating dummy certificates..."
  local HOST="$0"
  local LIVE_PATH="/etc/letsencrypt/live/$HOST"
  mkdir -p "$CERT_PATH/conf/live/$HOST"
  
  # run command
  docker-compose -f "$DOCKER_FILE" run --rm --entrypoint "\
    openssl req -x509 -nodes -newkey rsa:1024 -days 90\
      -keyout '$LIVE_PATH/privkey.pem' \
      -out '$LIVE_PATH/fullchain.pem' \
      -subj '/CN=localhost'" certbot
}

reload_nginx() {
  info "Reloading nginx..."
  docker-compose -f $DOCKER_FILE exec -d nginx nginx -s reload
}

start_ngingx() {
  warn "Starting nginx..."
  docker-compose -f $DOCKER_FILE up --force-recreate -d nginx
}

create_valid_certs() {
  # create nginx conf file 
  conf_file="$NGINX_PATH/$APP_SERVICE.conf"
  
  cp $NGINX_TEMPLATE_PATH $conf_file
  sed -i "s/APP_HOST/$APP_HOST/g" $conf_file
  sed -i "s/APP_PORT/$APP_PORT/g" $conf_file
  sed -i "s/APP_SERVICE/$APP_SERVICE/g" $conf_file

  # get TLS data
  if [ ! -e "$CERT_PATH/conf/options-ssl-nginx.conf" ] || [ ! -e "$CERT_PATH/conf/ssl-dhparams.pem" ]; then
    info "Downloading recommended TLS parameters..."
    mkdir -p "$CERT_PATH/conf"
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/options-ssl-nginx.conf > "$CERT_PATH/conf/options-ssl-nginx.conf"
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/ssl-dhparams.pem > "$CERT_PATH/conf/ssl-dhparams.pem"
  fi

  # create local certs
  create_dummy_certs "$APP_HOST"
  reload_nginx

  # delete dummy certificates
  info "Deleting dummy certificate..."
  docker-compose -f $DOCKER_FILE run --rm --entrypoint "\
    rm -Rf /etc/letsencrypt/live/$APP_HOST && \
    rm -Rf /etc/letsencrypt/archive/$APP_HOST && \
    rm -Rf /etc/letsencrypt/renewal/$APP_HOST.conf" certbot

  # Create LetsEncrypt certificates
  warn "Requesting Let's Encrypt certificate for '$APP_HOST'" 
  domain_args=""
  for domain in "${DOMAINS[@]}"; do
    domain_args="$domain_args -d $domain"
  done

  # Email arg
  case "$USER_EMAIL" in
    "") email_arg="--register-unsafely-without-email" ;;
    *) email_arg="--email $USER_EMAIL" ;;
  esac

  # Enable staging if needed
  if [[ $STAGING == "1" ]]; then 
    staging_arg="--staging"; 
  fi
  # install certificates
  docker-compose -f $DOCKER_FILE run --rm --entrypoint "\
    certbot certonly --webroot -w /var/www/certbot \
      $staging_arg \
      $email_arg \
      $domain_args \
      --rsa-key-size $rsa_key_size \
      --agree-tos \
      --force-renewal" certbot \
      && succ "Success for {$domain}\n" \
      || create_dummy_certs "$APP_HOST"

  # reload nginx
  reload_nginx
  echo
}

#########################################
# run script
echo "=================== ${APP_HOST} ==================="
start_ngingx
create_valid_certs