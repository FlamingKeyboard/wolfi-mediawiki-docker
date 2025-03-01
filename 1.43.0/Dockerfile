FROM cgr.dev/chainguard/wolfi-base:latest

# Install necessary packages for MediaWiki
RUN apk update && \
    apk add --no-cache \
    php-8.4 \
    php-8.4-fpm \
    php-8.4-curl \
    php-8.4-gd \
    php-8.4-intl \
    php-8.4-mbstring \
    php-8.4-xml \
    php-8.4-zip \
    php-8.4-mysqli \
    php-8.4-opcache \
    php-8.4-calendar \
    php-8.4-apcu \
    php-8.4-mysqlnd \
    php-8.4-ctype \
    php-8.4-iconv \
    php-8.4-fileinfo \
    php-8.4-dom \
    nginx \
    wget \
    git \
    diffutils \
    ca-certificates \
    shadow \
    imagemagick \
    python3

# Create both mediawiki and nginx users/groups
RUN groupadd -r mediawiki && \
    useradd -r -g mediawiki -d /var/www/html -s /sbin/nologin mediawiki && \
    groupadd -r nginx && \
    useradd -r -g nginx -d /var/lib/nginx -s /sbin/nologin nginx

# Create necessary directories for Nginx
RUN mkdir -p /var/www/html /var/www/data /var/log/nginx /run/nginx \
    /var/lib/nginx/tmp/client_body /var/lib/nginx/tmp/proxy \
    /var/lib/nginx/tmp/fastcgi /var/lib/nginx/logs && \
    chown -R mediawiki:mediawiki /var/www/html /var/www/data && \
    chown -R nginx:nginx /var/log/nginx /run/nginx /var/lib/nginx

# Download and install MediaWiki
ENV MEDIAWIKI_MAJOR_VERSION=1.43
ENV MEDIAWIKI_VERSION=1.43.0

RUN wget "https://releases.wikimedia.org/mediawiki/${MEDIAWIKI_MAJOR_VERSION}/mediawiki-${MEDIAWIKI_VERSION}.tar.gz" -O /tmp/mediawiki.tar.gz && \
    tar -xzf /tmp/mediawiki.tar.gz --strip-components=1 -C /var/www/html && \
    rm /tmp/mediawiki.tar.gz && \
    chown -R mediawiki:mediawiki /var/www/html

# Configure PHP
RUN mkdir -p /etc/php/8.4/conf.d && \
    echo 'opcache.memory_consumption=128' >> /etc/php/8.4/conf.d/opcache-recommended.ini && \
    echo 'opcache.interned_strings_buffer=8' >> /etc/php/8.4/conf.d/opcache-recommended.ini && \
    echo 'opcache.max_accelerated_files=4000' >> /etc/php/8.4/conf.d/opcache-recommended.ini && \
    echo 'opcache.revalidate_freq=60' >> /etc/php/8.4/conf.d/opcache-recommended.ini

# Create an extension directory for all PHP extensions to load them in the correct order
RUN mkdir -p /etc/php/8.4/conf.d/extensions && \
    echo 'extension=mysqlnd.so' > /etc/php/8.4/conf.d/extensions/10-mysqlnd.ini && \
    echo 'extension=mysqli.so' > /etc/php/8.4/conf.d/extensions/20-mysqli.ini && \
    echo 'extension=calendar.so' > /etc/php/8.4/conf.d/extensions/20-calendar.ini && \
    echo 'extension=apcu.so' > /etc/php/8.4/conf.d/extensions/20-apcu.ini && \
    echo 'extension=ctype.so' > /etc/php/8.4/conf.d/extensions/20-ctype.ini && \
    echo 'extension=iconv.so' > /etc/php/8.4/conf.d/extensions/20-iconv.ini && \
    echo 'extension=fileinfo.so' > /etc/php/8.4/conf.d/extensions/20-fileinfo.ini && \
    echo 'extension=dom.so' > /etc/php/8.4/conf.d/extensions/20-dom.ini

# Remove any default nginx configurations that might be causing conflicts
RUN rm -f /etc/nginx/nginx.conf /etc/nginx/conf.d/*.conf 2>/dev/null || true

# Create nginx.conf with nginx user explicitly specified and security headers
RUN echo 'user nginx nginx;' > /etc/nginx/nginx.conf && \
    echo 'worker_processes auto;' >> /etc/nginx/nginx.conf && \
    echo 'pid /run/nginx/nginx.pid;' >> /etc/nginx/nginx.conf && \
    echo 'events {' >> /etc/nginx/nginx.conf && \
    echo '    worker_connections 768;' >> /etc/nginx/nginx.conf && \
    echo '}' >> /etc/nginx/nginx.conf && \
    echo 'http {' >> /etc/nginx/nginx.conf && \
    echo '    sendfile on;' >> /etc/nginx/nginx.conf && \
    echo '    tcp_nopush on;' >> /etc/nginx/nginx.conf && \
    echo '    tcp_nodelay on;' >> /etc/nginx/nginx.conf && \
    echo '    keepalive_timeout 65;' >> /etc/nginx/nginx.conf && \
    echo '    types_hash_max_size 2048;' >> /etc/nginx/nginx.conf && \
    echo '    include /etc/nginx/mime.types;' >> /etc/nginx/nginx.conf && \
    echo '    default_type application/octet-stream;' >> /etc/nginx/nginx.conf && \
    echo '    server {' >> /etc/nginx/nginx.conf && \
    echo '        listen 80;' >> /etc/nginx/nginx.conf && \
    echo '        root /var/www/html;' >> /etc/nginx/nginx.conf && \
    echo '        index index.php;' >> /etc/nginx/nginx.conf && \
    echo '        server_name _;' >> /etc/nginx/nginx.conf && \
    echo '        location / {' >> /etc/nginx/nginx.conf && \
    echo '            try_files $uri $uri/ /index.php?$args;' >> /etc/nginx/nginx.conf && \
    echo '        }' >> /etc/nginx/nginx.conf && \
    echo '        location ~ \.php$ {' >> /etc/nginx/nginx.conf && \
    echo '            include fastcgi_params;' >> /etc/nginx/nginx.conf && \
    echo '            fastcgi_pass 127.0.0.1:9000;' >> /etc/nginx/nginx.conf && \
    echo '            fastcgi_index index.php;' >> /etc/nginx/nginx.conf && \
    echo '            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;' >> /etc/nginx/nginx.conf && \
    echo '        }' >> /etc/nginx/nginx.conf && \
    echo '        # Security headers for uploads' >> /etc/nginx/nginx.conf && \
    echo '        location /images/ {' >> /etc/nginx/nginx.conf && \
    echo '            add_header X-Content-Type-Options "nosniff" always;' >> /etc/nginx/nginx.conf && \
    echo '            # Disable PHP execution in uploads directory' >> /etc/nginx/nginx.conf && \
    echo '            location ~ \.php$ {' >> /etc/nginx/nginx.conf && \
    echo '                deny all;' >> /etc/nginx/nginx.conf && \
    echo '            }' >> /etc/nginx/nginx.conf && \
    echo '        }' >> /etc/nginx/nginx.conf && \
    echo '    }' >> /etc/nginx/nginx.conf && \
    echo '}' >> /etc/nginx/nginx.conf

# Create a basic fastcgi_params file if it doesn't exist
RUN echo 'fastcgi_param  QUERY_STRING       $query_string;' > /etc/nginx/fastcgi_params && \
    echo 'fastcgi_param  REQUEST_METHOD     $request_method;' >> /etc/nginx/fastcgi_params && \
    echo 'fastcgi_param  CONTENT_TYPE       $content_type;' >> /etc/nginx/fastcgi_params && \
    echo 'fastcgi_param  CONTENT_LENGTH     $content_length;' >> /etc/nginx/fastcgi_params && \
    echo 'fastcgi_param  SCRIPT_NAME        $fastcgi_script_name;' >> /etc/nginx/fastcgi_params && \
    echo 'fastcgi_param  REQUEST_URI        $request_uri;' >> /etc/nginx/fastcgi_params && \
    echo 'fastcgi_param  DOCUMENT_URI       $document_uri;' >> /etc/nginx/fastcgi_params && \
    echo 'fastcgi_param  DOCUMENT_ROOT      $document_root;' >> /etc/nginx/fastcgi_params && \
    echo 'fastcgi_param  SERVER_PROTOCOL    $server_protocol;' >> /etc/nginx/fastcgi_params && \
    echo 'fastcgi_param  GATEWAY_INTERFACE  CGI/1.1;' >> /etc/nginx/fastcgi_params && \
    echo 'fastcgi_param  SERVER_SOFTWARE    nginx/$nginx_version;' >> /etc/nginx/fastcgi_params && \
    echo 'fastcgi_param  REMOTE_ADDR        $remote_addr;' >> /etc/nginx/fastcgi_params && \
    echo 'fastcgi_param  REMOTE_PORT        $remote_port;' >> /etc/nginx/fastcgi_params && \
    echo 'fastcgi_param  SERVER_ADDR        $server_addr;' >> /etc/nginx/fastcgi_params && \
    echo 'fastcgi_param  SERVER_PORT        $server_port;' >> /etc/nginx/fastcgi_params && \
    echo 'fastcgi_param  SERVER_NAME        $server_name;' >> /etc/nginx/fastcgi_params

# Make web files accessible to nginx user
RUN chmod -R 755 /var/www/html && \
    chown -R mediawiki:mediawiki /var/www/html && \
    chmod -R g+r /var/www/html && \
    usermod -a -G mediawiki nginx

# Create uploads directory and set permissions
RUN mkdir -p /var/www/html/images/tmp /var/www/html/images/thumb && \
    chown -R mediawiki:mediawiki /var/www/html/images && \
    chmod -R 755 /var/www/html/images

# Create a basic PHP info page for testing
RUN echo "<?php phpinfo(); ?>" > /var/www/html/info.php && \
    chown mediawiki:mediawiki /var/www/html/info.php

# Create entrypoint script with correct PHP-FPM configuration for Wolfi
RUN echo '#!/bin/sh' > /entrypoint.sh && \
    echo 'set -e' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Configure PHP-FPM to run as mediawiki user' >> /entrypoint.sh && \
    echo 'mkdir -p /run/php-fpm' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Create PHP-FPM pool configuration' >> /entrypoint.sh && \
    echo 'mkdir -p /etc/php/8.4/php-fpm.d/' >> /entrypoint.sh && \
    echo 'echo "[www]" > /etc/php/8.4/php-fpm.d/www.conf' >> /entrypoint.sh && \
    echo 'echo "user = mediawiki" >> /etc/php/8.4/php-fpm.d/www.conf' >> /entrypoint.sh && \
    echo 'echo "group = mediawiki" >> /etc/php/8.4/php-fpm.d/www.conf' >> /entrypoint.sh && \
    echo 'echo "listen = 127.0.0.1:9000" >> /etc/php/8.4/php-fpm.d/www.conf' >> /entrypoint.sh && \
    echo 'echo "pm = dynamic" >> /etc/php/8.4/php-fpm.d/www.conf' >> /entrypoint.sh && \
    echo 'echo "pm.max_children = 5" >> /etc/php/8.4/php-fpm.d/www.conf' >> /entrypoint.sh && \
    echo 'echo "pm.start_servers = 2" >> /etc/php/8.4/php-fpm.d/www.conf' >> /entrypoint.sh && \
    echo 'echo "pm.min_spare_servers = 1" >> /etc/php/8.4/php-fpm.d/www.conf' >> /entrypoint.sh && \
    echo 'echo "pm.max_spare_servers = 3" >> /etc/php/8.4/php-fpm.d/www.conf' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Find PHP-FPM executable' >> /entrypoint.sh && \
    echo 'echo "Looking for PHP-FPM executable..."' >> /entrypoint.sh && \
    echo 'if [ -x "/usr/bin/php-fpm8.4" ]; then' >> /entrypoint.sh && \
    echo '  PHP_FPM_BIN="/usr/bin/php-fpm8.4"' >> /entrypoint.sh && \
    echo 'elif [ -x "/usr/bin/php-fpm" ]; then' >> /entrypoint.sh && \
    echo '  PHP_FPM_BIN="/usr/bin/php-fpm"' >> /entrypoint.sh && \
    echo 'elif [ -x "/usr/sbin/php-fpm8.4" ]; then' >> /entrypoint.sh && \
    echo '  PHP_FPM_BIN="/usr/sbin/php-fpm8.4"' >> /entrypoint.sh && \
    echo 'elif [ -x "/usr/sbin/php-fpm" ]; then' >> /entrypoint.sh && \
    echo '  PHP_FPM_BIN="/usr/sbin/php-fpm"' >> /entrypoint.sh && \
    echo 'else' >> /entrypoint.sh && \
    echo '  echo "PHP-FPM executable not found. Attempting to find it..."' >> /entrypoint.sh && \
    echo '  PHP_FPM_BIN=$(find /usr -name "php-fpm*" -type f -executable | grep -v "\.conf" | head -1)' >> /entrypoint.sh && \
    echo '  if [ -z "$PHP_FPM_BIN" ]; then' >> /entrypoint.sh && \
    echo '    echo "Error: PHP-FPM executable could not be found"' >> /entrypoint.sh && \
    echo '    exit 1' >> /entrypoint.sh && \
    echo '  fi' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    echo 'echo "Found PHP-FPM at: $PHP_FPM_BIN"' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo 'echo "Starting PHP-FPM with user: mediawiki"' >> /entrypoint.sh && \
    echo '$PHP_FPM_BIN --nodaemonize --fpm-config /etc/php/8.4/php-fpm.d/www.conf &' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo 'echo "Starting Nginx with user: nginx"' >> /entrypoint.sh && \
    echo 'nginx -g "daemon off;"' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

# Expose port for web access
EXPOSE 80

# Set working directory
WORKDIR /var/www/html

# Run entrypoint
ENTRYPOINT ["/entrypoint.sh"]