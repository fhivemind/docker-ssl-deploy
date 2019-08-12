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
# add warn messages
succ ()  { echo $(tput bold)$(tput setaf 2) $@ $(tput sgr 0) ; }
info ()  { echo $(tput bold)$(tput setaf 4) $@ $(tput sgr 0) ; }
warn ()  { echo $(tput bold)$(tput setaf 3) $@ $(tput sgr 0) ; }
error () { echo $(tput bold)$(tput setaf 1) $@ $(tput sgr 0) ; }

#########################################
# create functions
create_dummy_certs() {
  # variables
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
  echo "[[ NGINX ]] Reloading nginx..."
  docker-compose -f $DOCKER_FILE exec -d nginx nginx -s reload
}

start_ngingx() {
  echo "[[ NGINX ]] Starting nginx..."
  docker-compose -f $DOCKER_FILE up --force-recreate -d nginx
}

create_valid_certs() {
  # export variables
  local APP_HOST="$1" 
  local APP_PORT="$2" 
  local APP_SERVICE="$3"
  local USER_EMAIL="$4"
  local STAGING="$5"
  local DOMAINS="$6"

  # create nginx conf file 
  conf_file="$NGINX_PATH/$APP_SERVICE.conf"
  
  cp $NGINX_TEMPLATE_PATH $conf_file
  sed -i "s/APP_HOST/$APP_HOST/g" $conf_file
  sed -i "s/APP_PORT/$APP_PORT/g" $conf_file
  sed -i "s/APP_SERVICE/$APP_SERVICE/g" $conf_file

  # get TLS data
  if [ ! -e "$CERT_PATH/conf/options-ssl-nginx.conf" ] || [ ! -e "$CERT_PATH/conf/ssl-dhparams.pem" ]; then
    echo "[[ STATUS ]] Downloading recommended TLS parameters..."
    mkdir -p "$CERT_PATH/conf"
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/options-ssl-nginx.conf > "$CERT_PATH/conf/options-ssl-nginx.conf"
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/ssl-dhparams.pem > "$CERT_PATH/conf/ssl-dhparams.pem"
    echo
  fi

  # create local certs
  create_dummy_certs "$APP_HOST"
  reload_nginx

  # delete dummy certificates
  echo "[[ STATUS ]] Deleting dummy certificate..."
  docker-compose -f $DOCKER_FILE run --rm --entrypoint "\
    rm -Rf /etc/letsencrypt/live/$APP_HOST && \
    rm -Rf /etc/letsencrypt/archive/$APP_HOST && \
    rm -Rf /etc/letsencrypt/renewal/$APP_HOST.conf" certbot

  # Create LetsEncrypt certificates
  echo -e "[[ STATUS ]] Requesting Let's Encrypt certificate for $DOMAINS..."
  domain_args=""
  for domain in "${DOMAINS[@]}"; do
    domain_args="$domain_args -d $domain"
  done

  # Email arg
  case "$email" in
    "") email_arg="--register-unsafely-without-email" ;;
    *) email_arg="--email $email" ;;
  esac

  # Enable staging if needed
  if [[ $staging != "0" ]]; then 
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
      && echo -e "\n[[SUCCESS]] {$domain}\n" \
      || create_dummy_certs "$APP_HOST"

  # reload nginx
  reload_nginx
}


#create_valid_certs "example.com" "3000" "example-service" "rase@mail.com" "0" "domain.com www.domain.com nesto.nesto.com"