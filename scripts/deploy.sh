#!/bin/bash

# Boot nginx
echo "[[ NGINX ]] Starting nginx..."
docker-compose up --force-recreate -d nginx
docker-compose exec -d nginx nginx -s reload

# loop through config data
for file in ./data/*; do
  
  # initialize data
  source $file
  filename="${file##*/}"
  
  rsa_key_size=4096
  data_path="./certbot"

  # if called for specific host
  if [ -n "$1" ] && [ "$1" != "$APP_HOST" ]; then
    continue
  fi

  # DOTS=${domains//[^.]};
  # Generate nginx script from template for domains and subomains
  # if  [[ ${#DOTS} > 1 ]]; then
  #  echo "### Creating certificate template for subdomain $domains"
  #  HOSTNAME="${domains#*.}"
  #  envsubst "`printf '${%s} ' $(sh -c "env|cut -d'=' -f1")`" < ./nginx/app_sub.tmpl > "./nginx/$filename.conf"
  #  continue
  # else

    # export variables
    export APP_HOST="$APP_HOST" 
    export APP_PORT="$APP_PORT" 
    export APP_SERVICE="$APP_SERVICE"

    envsubst "`printf '${%s} ' $(sh -c "env|cut -d'=' -f1")`" < ./nginx/app.tmpl > "./nginx/$filename.conf"
  #fi
  
  if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
    echo "[[ STATUS ]] Downloading recommended TLS parameters..."
    mkdir -p "$data_path/conf"
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/options-ssl-nginx.conf > "$data_path/conf/options-ssl-nginx.conf"
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/ssl-dhparams.pem > "$data_path/conf/ssl-dhparams.pem"
    echo
  fi

  echo -e "==========================================================="
  echo "[[ GENERATING CERTIFICATES ]]     $domains" 
  echo -e "===========================================================\n"

  # self-signed certificates gen
  create_dummy_certs() {
    echo -e $1
    path="/etc/letsencrypt/live/$domains"
    mkdir -p "$data_path/conf/live/$domains"
    docker-compose run --rm --entrypoint "\
      openssl req -x509 -nodes -newkey rsa:1024 -days 90\
        -keyout '$path/privkey.pem' \
        -out '$path/fullchain.pem' \
        -subj '/CN=localhost'" certbot
    echo
  }

  # generate initial certificates  
  create_dummy_certs "[[ STATUS ]] Creating dummy certificates..."

  echo "[[ NGINX ]] Reloading nginx..."
  docker-compose exec -d nginx nginx -s reload

  # delete dummy certificates
  echo "[[ STATUS ]] Deleting dummy certificate..."
  docker-compose run --rm --entrypoint "\
    rm -Rf /etc/letsencrypt/live/$domains && \
    rm -Rf /etc/letsencrypt/archive/$domains && \
    rm -Rf /etc/letsencrypt/renewal/$domains.conf" certbot

  # Create LetsEncrypt certificates
  echo -e "[[ STATUS ]] Requesting Let's Encrypt certificate for $domains..."
  domain_args=""
  for domain in "${domains[@]}"; do
    domain_args="$domain_args -d $domain"
  done

  # Email arg
  case "$email" in
    "") email_arg="--register-unsafely-without-email" ;;
    *) email_arg="--email $email" ;;
  esac

  # Enable staging if needed
  if [ $staging != "0" ]; then staging_arg="--staging"; fi

  # Obtain LE cert
  docker-compose run --rm --entrypoint "\
    certbot certonly --webroot -w /var/www/certbot \
      $staging_arg \
      $email_arg \
      $domain_args \
      --rsa-key-size $rsa_key_size \
      --agree-tos \
      --force-renewal" certbot \
      && echo -e "\n[[SUCCESS]] {$domain}\n" \
      || create_dummy_certs "\n[[FAILURE]] Restoring previous self-signed certificates.\n"

  echo
done

# Reboot nginx
echo "[[ NGINX ]] Reloading nginx..."
docker-compose exec -d nginx nginx -s reload