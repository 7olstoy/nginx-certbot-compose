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
        --service*|-s=*)
            service="${arg#*=}"
            ;;
        --port*|-p=*)
            port="${arg#*=}"
            ;;
        *)
            ;;
    esac
done

if [[ -z "${domains}" ]] || [[ -z "${email}" ]] || [[ -z "${service}" ]]; then
    echo "Please use --domains=, --email=, --service= and --port= options"
    exit
fi

rsa_key_size=4096
data_path="./certbot"

if ! [[ -d ./certbot/conf ]]; then
    echo "Create /certbot/conf.."
    mkdir ./certbot/conf
fi

if [[ -z $(docker-compose ps | grep nginx) ]]; then
    echo "Starting nginx ..."
    docker-compose up --force-recreate -d nginx
fi

declare -a domains="( ${domains} )"

echo "Requesting Let's Encrypt certificate for $domain ..."

# Select appropriate email arg
case "$email" in
  "") email_arg="--register-unsafely-without-email" ;;
  *) email_arg="--email $email" ;;
esac

for domain in "${domains[@]}"; do
    if ! [[ -d ./certbot/conf/live/${domain} ]]; then
        docker-compose run --rm --entrypoint "\
            certbot certonly -n --webroot -w /var/www/certbot \
              $email_arg \
              -d $domain \
              --rsa-key-size $rsa_key_size \
              --agree-tos \
              --force-renewal" certbot
        if [[ -d ./certbot/conf/live/${domain} ]]; then
            if ! [[ -f ./nginx/conf.d/${domain}.conf ]]; then
                echo 'server {
    listen 443 ssl http2;

    try_files $uri $uri/ =404;

    access_log off;
    error_log /var/log/nginx/error.log;

    server_name HELLO_DOMAIN;

    #auth_basic	"KEEP CALM & GO AWAY";
    #auth_basic_user_file ./conf.d/.htpasswd; 

    location / {
        resolver 127.0.0.11 valid=30s;
        set $docker HELLO_SERVICE;
        proxy_pass http://$docker:$port;
        proxy_set_header    Host                $http_host;
        proxy_set_header    X-Real-IP           $remote_addr;
        proxy_set_header    X-Forwarded-For     $proxy_add_x_forwarded_for;
    }

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
                sed -i 's/'HELLO_SERVICE'/'${service}'/' ./nginx/conf.d/${domain}.conf
            else
                echo "Nginx conf for ${domain} is already exist"
            fi
        else
            echo "SSL for ${domain} is not ready"
            exit 1
        fi
    else
        echo "SSL for ${domain} is already exist"
        exit 0
    fi
done

echo "Reloading nginx ..."
docker-compose exec nginx nginx -s reload
