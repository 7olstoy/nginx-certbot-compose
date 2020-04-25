# nginx-certbot-compose

Docker-compose way to setup NGINX with SSL by Certbot and auto-renew.

## Setup
Add new docker network for use NGINX with other containers:

```docker network create nginx_proxy```

Run script with your parameters:

* one ore more domain names;
* your email for SSL notification;
* your service IP or name for proxy_pass:

```./init.sh --domains="domain.com domain2.com" --email="admin@admin.com" --service="backend:9000"```

You can also add new domains to this working compose by new running this init.sh.

```./init.sh --domains="new.domain.com" --email="admin@admin.com" --service="newbackend:9000"```
