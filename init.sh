if ! [ -x "$(command -v docker-compose)" ]; then
  echo 'Error: docker-compose is not installed.' >&2
  exit 1
fi

for arg in "$@" ; do
    case "$arg" in
        --domains=*|-d=*)
            domains="${arg#*=}"
            ;;
        --email=*|-e=*)
            email="${arg#*=}"
            ;;
        *)
            ;;
    esac
done

if [[ -z "${domains}" ]] || [[ -z "${email}" ]]; then
    echo "Please use --domain= and --email= options"
    exit
fi

rsa_key_size=4096
data_path="./certbot"

echo "### Trancate ./certbot folder ..."
rm -rf ./certbot/*
mkdir ./certbot/conf
mkdir ./certbot/www


echo "### Starting nginx ..."
docker-compose up --force-recreate -d nginx

declare -a domains="( $domains )"

echo "### Requesting Let's Encrypt certificate for $domain ..."

#Join $domains to -d args
domain_args=""
for domain in "${domains[@]}"; do
  domain_args="$domain_args -d $domain"
done

# Select appropriate email arg
case "$email" in
  "") email_arg="--register-unsafely-without-email" ;;
  *) email_arg="--email $email" ;;
esac

for domain in "${domains[@]}"; do
  docker-compose run --rm --entrypoint "\
    certbot certonly -n --webroot -w /var/www/certbot \
      $email_arg \
      $domain_args \
      --rsa-key-size $rsa_key_size \
      --agree-tos \
      --force-renewal" certbot
  if [[ -d "./certbot/conf/live/${domain}" ]]; then
    echo 'server {
    listen 443 ssl http2;

    try_files $uri $uri/ =404;

    access_log off;
    error_log /var/log/nginx/error.log;

    server_name HELLO_DOMAIN;

    #auth_basic	"KEEP CALM & GO AWAY";
    #auth_basic_user_file ./conf.d/.htpasswd; 

    location / {
        return 403;
        #proxy_pass http://something:port;
        #proxy_set_header    Host                $http_host;
        #proxy_set_header    X-Real-IP           $remote_addr;
        #proxy_set_header    X-Forwarded-For     $proxy_add_x_forwarded_for;
    }

    #location ~ \.php$ {
    #    fastcgi_split_path_info ^(.+\.php)(/.+)$;
    #    try_files $fastcgi_script_name =404;
    #    set $path_info $fastcgi_path_info;
    #    fastcgi_param PATH_INFO $path_info;
    #    fastcgi_index index.php;
    #
    #    fastcgi_param  SCRIPT_FILENAME    $document_root$fastcgi_script_name;
    #    fastcgi_param  QUERY_STRING       $query_string;
    #    fastcgi_param  REQUEST_METHOD     $request_method;
    #    fastcgi_param  CONTENT_TYPE       $content_type;
    #    fastcgi_param  CONTENT_LENGTH     $content_length;
    #
    #    fastcgi_param  SCRIPT_NAME        $fastcgi_script_name;
    #    fastcgi_param  REQUEST_URI        $request_uri;
    #    fastcgi_param  DOCUMENT_URI       $document_uri;
    #    fastcgi_param  DOCUMENT_ROOT      $document_root;
    #    fastcgi_param  SERVER_PROTOCOL    $server_protocol;
    #    fastcgi_param  HTTPS              $https if_not_empty;
    #
    #    fastcgi_param  GATEWAY_INTERFACE  CGI/1.1;
    #    fastcgi_param  SERVER_SOFTWARE    nginx/$nginx_version;
    #
    #    fastcgi_param  REMOTE_ADDR        $remote_addr;
    #    fastcgi_param  REMOTE_PORT        $remote_port;
    #    fastcgi_param  SERVER_ADDR        $server_addr;
    #    fastcgi_param  SERVER_PORT        $server_port;
    #    fastcgi_param  SERVER_NAME        $server_name;
    #
    #    fastcgi_param  REDIRECT_STATUS    200;
    #
    #    fastcgi_pass php-fpm:9000;
    #}

    ssl_certificate /etc/letsencrypt/live/HELLO_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/HELLO_DOMAIN/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/HELLO_DOMAIN/fullchain.pem;

    ssl_session_cache shared:le_nginx_SSL:10m;
    ssl_session_timeout 1440m;
    ssl_session_tickets on;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA";
}' > ./nginx/conf.d/${domain}.conf
    sed -i 's/'HELLO_DOMAIN'/'${domain}'/' ./nginx/conf.d/${domain}.conf
  fi
done

echo "### Reloading nginx ..."
docker-compose exec nginx nginx -s reload
