FROM cgr.dev/chainguard/wolfi-base:latest

# Allow build-time customization of PHP version
ARG PHP_VERSION=8.4
ENV PHP_VERSION=${PHP_VERSION}

# Allow build-time customization of MediaWiki version
ARG MEDIAWIKI_VERSION=1.43.0
ENV MEDIAWIKI_VERSION=${MEDIAWIKI_VERSION}
ENV MEDIAWIKI_MAJOR_VERSION=$(echo ${MEDIAWIKI_VERSION} | cut -d. -f1,2)

# Install necessary packages for MediaWiki
# Generate a list of required PHP extensions
RUN echo "Detected PHP version: ${PHP_VERSION}" && \
    apk update && \
    # Install base packages first
    apk add --no-cache \
    nginx \
    wget \
    git \
    diffutils \
    ca-certificates \
    shadow \
    busybox \
    imagemagick \
    python3 \
    curl \
    # Install PHP and its extensions - try first with versioned format php-X.Y
    && (apk add --no-cache php-${PHP_VERSION} php-${PHP_VERSION}-fpm || true) \
    # If the above fails, try with php-X.Y-X.Y.Z format
    && if ! command -v php > /dev/null; then \
          echo "Trying alternative PHP package naming..."; \
          # Find the actual package name for this version
          PHP_PKG=$(apk search php | grep -E "^php-${PHP_VERSION}-${PHP_VERSION}" | sort -V | tail -1); \
          if [ -n "$PHP_PKG" ]; then \
            echo "Found PHP package: $PHP_PKG"; \
            apk add --no-cache $PHP_PKG; \
          else \
            echo "Could not find PHP package for version ${PHP_VERSION}"; \
            exit 1; \
          fi; \
       fi \
    # Now install required extensions - try both naming formats
    && for ext in fpm curl gd intl mbstring xml zip mysqli opcache calendar apcu mysqlnd ctype iconv fileinfo dom; do \
         echo "Installing extension: $ext"; \
         apk add --no-cache php-${PHP_VERSION}-${ext} || \
         apk add --no-cache $(apk search php | grep -E "^php-${PHP_VERSION}-${ext}-[0-9]+" | sort -V | tail -1) || \
         echo "Warning: Could not install PHP extension $ext"; \
       done

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
RUN wget "https://releases.wikimedia.org/mediawiki/${MEDIAWIKI_MAJOR_VERSION}/mediawiki-${MEDIAWIKI_VERSION}.tar.gz" -O /tmp/mediawiki.tar.gz && \
    tar -xzf /tmp/mediawiki.tar.gz --strip-components=1 -C /var/www/html && \
    rm /tmp/mediawiki.tar.gz && \
    chown -R mediawiki:mediawiki /var/www/html

# Configure PHP
RUN mkdir -p /etc/php/${PHP_VERSION}/conf.d && \
    echo 'opcache.memory_consumption=128' >> /etc/php/${PHP_VERSION}/conf.d/opcache-recommended.ini && \
    echo 'opcache.interned_strings_buffer=8' >> /etc/php/${PHP_VERSION}/conf.d/opcache-recommended.ini && \
    echo 'opcache.max_accelerated_files=4000' >> /etc/php/${PHP_VERSION}/conf.d/opcache-recommended.ini && \
    echo 'opcache.revalidate_freq=60' >> /etc/php/${PHP_VERSION}/conf.d/opcache-recommended.ini

# Create an extension directory for all PHP extensions to load them in the correct order
RUN mkdir -p /etc/php/${PHP_VERSION}/conf.d/extensions && \
    echo 'extension=mysqlnd.so' > /etc/php/${PHP_VERSION}/conf.d/extensions/10-mysqlnd.ini && \
    echo 'extension=mysqli.so' > /etc/php/${PHP_VERSION}/conf.d/extensions/20-mysqli.ini && \
    echo 'extension=calendar.so' > /etc/php/${PHP_VERSION}/conf.d/extensions/20-calendar.ini && \
    echo 'extension=apcu.so' > /etc/php/${PHP_VERSION}/conf.d/extensions/20-apcu.ini && \
    echo 'extension=ctype.so' > /etc/php/${PHP_VERSION}/conf.d/extensions/20-ctype.ini && \
    echo 'extension=iconv.so' > /etc/php/${PHP_VERSION}/conf.d/extensions/20-iconv.ini && \
    echo 'extension=fileinfo.so' > /etc/php/${PHP_VERSION}/conf.d/extensions/20-fileinfo.ini && \
    echo 'extension=dom.so' > /etc/php/${PHP_VERSION}/conf.d/extensions/20-dom.ini

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

# Create a comprehensive health check script
RUN echo '#!/bin/sh' > /healthcheck.sh && \
    echo 'set -e' >> /healthcheck.sh && \
    echo '' >> /healthcheck.sh && \
    echo '# Check if nginx is running' >> /healthcheck.sh && \
    echo 'if ! ps aux | grep -v grep | grep -q nginx; then' >> /healthcheck.sh && \
    echo '  echo "Health check failed: Nginx is not running"' >> /healthcheck.sh && \
    echo '  exit 1' >> /healthcheck.sh && \
    echo 'fi' >> /healthcheck.sh && \
    echo '' >> /healthcheck.sh && \
    echo '# Check if PHP-FPM is running' >> /healthcheck.sh && \
    echo 'if ! ps aux | grep -v grep | grep -q php-fpm; then' >> /healthcheck.sh && \
    echo '  echo "Health check failed: PHP-FPM is not running"' >> /healthcheck.sh && \
    echo '  exit 1' >> /healthcheck.sh && \
    echo 'fi' >> /healthcheck.sh && \
    echo '' >> /healthcheck.sh && \
    echo '# Check if we can access the info.php page' >> /healthcheck.sh && \
    echo 'if ! curl -s -f http://localhost/info.php | grep -q "PHP Version"; then' >> /healthcheck.sh && \
    echo '  echo "Health check failed: Cannot access PHP info page"' >> /healthcheck.sh && \
    echo '  exit 1' >> /healthcheck.sh && \
    echo 'fi' >> /healthcheck.sh && \
    echo '' >> /healthcheck.sh && \
    echo '# Check if we can ping localhost' >> /healthcheck.sh && \
    echo 'if ! ping -c 1 localhost > /dev/null 2>&1; then' >> /healthcheck.sh && \
    echo '  echo "Health check failed: Cannot ping localhost"' >> /healthcheck.sh && \
    echo '  exit 1' >> /healthcheck.sh && \
    echo 'fi' >> /healthcheck.sh && \
    echo '' >> /healthcheck.sh && \
    echo '# Check if MediaWiki setup page is accessible' >> /healthcheck.sh && \
    echo 'if curl -s http://localhost/mw-config/index.php?page=Welcome 2>/dev/null | grep -q "The environment has been checked"; then' >> /healthcheck.sh && \
    echo '  echo "MediaWiki setup page is accessible and environment check passed"' >> /healthcheck.sh && \
    echo 'elif curl -s http://localhost/mw-config/index.php?page=Welcome 2>/dev/null | grep -q "cdx-message__content"; then' >> /healthcheck.sh && \
    echo '  echo "MediaWiki setup page is accessible"' >> /healthcheck.sh && \
    echo 'else' >> /healthcheck.sh && \
    echo '  # Only warn, don't fail - the config might be complete already' >> /healthcheck.sh && \
    echo '  echo "Warning: MediaWiki setup page is not accessible, but this might be expected if already configured"' >> /healthcheck.sh && \
    echo 'fi' >> /healthcheck.sh && \
    echo '' >> /healthcheck.sh && \
    echo 'echo "Health check passed"' >> /healthcheck.sh && \
    echo 'exit 0' >> /healthcheck.sh && \
    chmod +x /healthcheck.sh

# Create entrypoint script with correct PHP-FPM configuration for Wolfi
RUN echo '#!/bin/sh' > /entrypoint.sh && \
    echo 'set -e' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Configure PHP-FPM to run as mediawiki user' >> /entrypoint.sh && \
    echo 'mkdir -p /run/php-fpm' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Create PHP-FPM pool configuration' >> /entrypoint.sh && \
    echo "mkdir -p /etc/php/${PHP_VERSION}/php-fpm.d/" >> /entrypoint.sh && \
    echo "echo \"[www]\" > /etc/php/${PHP_VERSION}/php-fpm.d/www.conf" >> /entrypoint.sh && \
    echo "echo \"user = mediawiki\" >> /etc/php/${PHP_VERSION}/php-fpm.d/www.conf" >> /entrypoint.sh && \
    echo "echo \"group = mediawiki\" >> /etc/php/${PHP_VERSION}/php-fpm.d/www.conf" >> /entrypoint.sh && \
    echo "echo \"listen = 127.0.0.1:9000\" >> /etc/php/${PHP_VERSION}/php-fpm.d/www.conf" >> /entrypoint.sh && \
    echo "echo \"pm = dynamic\" >> /etc/php/${PHP_VERSION}/php-fpm.d/www.conf" >> /entrypoint.sh && \
    echo "echo \"pm.max_children = 5\" >> /etc/php/${PHP_VERSION}/php-fpm.d/www.conf" >> /entrypoint.sh && \
    echo "echo \"pm.start_servers = 2\" >> /etc/php/${PHP_VERSION}/php-fpm.d/www.conf" >> /entrypoint.sh && \
    echo "echo \"pm.min_spare_servers = 1\" >> /etc/php/${PHP_VERSION}/php-fpm.d/www.conf" >> /entrypoint.sh && \
    echo "echo \"pm.max_spare_servers = 3\" >> /etc/php/${PHP_VERSION}/php-fpm.d/www.conf" >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Find PHP-FPM executable' >> /entrypoint.sh && \
    echo 'echo "Looking for PHP-FPM executable..."' >> /entrypoint.sh && \
    echo "if [ -x \"/usr/bin/php-fpm${PHP_VERSION}\" ]; then" >> /entrypoint.sh && \
    echo "  PHP_FPM_BIN=\"/usr/bin/php-fpm${PHP_VERSION}\"" >> /entrypoint.sh && \
    echo 'elif [ -x "/usr/bin/php-fpm" ]; then' >> /entrypoint.sh && \
    echo '  PHP_FPM_BIN="/usr/bin/php-fpm"' >> /entrypoint.sh && \
    echo "elif [ -x \"/usr/sbin/php-fpm${PHP_VERSION}\" ]; then" >> /entrypoint.sh && \
    echo "  PHP_FPM_BIN=\"/usr/sbin/php-fpm${PHP_VERSION}\"" >> /entrypoint.sh && \
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
    echo "CONF_PATH=\"/etc/php/${PHP_VERSION}/php-fpm.d/www.conf\"" >> /entrypoint.sh && \
    echo '$PHP_FPM_BIN --nodaemonize --fpm-config $CONF_PATH &' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo 'echo "Starting Nginx with user: nginx"' >> /entrypoint.sh && \
    echo 'nginx -g "daemon off;"' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

# Add health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /healthcheck.sh

# Expose port for web access
EXPOSE 80

# Set working directory
WORKDIR /var/www/html

# Run entrypoint
ENTRYPOINT ["/entrypoint.sh"]