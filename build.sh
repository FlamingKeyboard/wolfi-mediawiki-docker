#!/bin/bash
set -e

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Parse command-line arguments
DOCKERHUB_USERNAME=""
DOCKERHUB_TOKEN=""
AUTO_PUSH=false
OUTPUT_VERSIONS=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --username)
      DOCKERHUB_USERNAME="$2"
      shift 2
      ;;
    --token)
      DOCKERHUB_TOKEN="$2"
      shift 2
      ;;
    --auto-push)
      AUTO_PUSH=true
      shift
      ;;
    --output-versions)
      OUTPUT_VERSIONS=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Check environment variables if not provided as arguments
if [ -z "$DOCKERHUB_USERNAME" ] && [ -n "$DOCKER_USERNAME" ]; then
  DOCKERHUB_USERNAME="$DOCKER_USERNAME"
fi

if [ -z "$DOCKERHUB_TOKEN" ] && [ -n "$DOCKER_TOKEN" ]; then
  DOCKERHUB_TOKEN="$DOCKER_TOKEN"
fi

# Determine if we should auto-push
if [ -n "$DOCKERHUB_USERNAME" ] && [ -n "$DOCKERHUB_TOKEN" ]; then
  AUTO_PUSH=true
fi

echo "=== Wolfi MediaWiki Docker Build Pipeline ==="
echo "This script will build, test, and push the MediaWiki Docker image"
echo "=============================================="

# Function to get latest PHP version available in Wolfi
get_latest_php_version() {
    echo "Detecting latest PHP version in Wolfi..." >&2
    local php_version=$(docker run --rm cgr.dev/chainguard/wolfi-base:latest sh -c "
        apk update > /dev/null
        # Look for packages with pattern php-X.Y-X.Y.Z-rN
        PHP_VER=\$(apk search php | grep -E '^php-[0-9]+\\.[0-9]+-[0-9]+' | cut -d'-' -f2 | sort -V | tail -1)
        # If that fails, try alternative patterns
        if [ -z \"\$PHP_VER\" ]; then
            PHP_VER=\$(apk search php | grep -E '^php-[0-9]+\\.[0-9]+\\.' | head -1 | cut -d'-' -f2)
        fi
        echo \$PHP_VER
    ")
    if [ -z "$php_version" ]; then
        echo "Failed to detect PHP version, using default" >&2
        php_version="8.4"
    fi
    echo "$php_version"
}

# Function to get latest MediaWiki version
get_latest_mediawiki_version() {
    echo "Detecting latest MediaWiki version..." >&2
    
    # Try to fetch with curl first
    local latest_major=$(curl -s --connect-timeout 10 https://releases.wikimedia.org/mediawiki/ | grep -oP '(?<=href=")[0-9]+\.[0-9]+(?=/)' | sort -V | tail -1)
    
    # If curl fails, try with wget as fallback
    if [ -z "$latest_major" ]; then
        echo "Curl failed, trying wget..." >&2
        latest_major=$(wget -qO- https://releases.wikimedia.org/mediawiki/ 2>/dev/null | grep -oP '(?<=href=")[0-9]+\.[0-9]+(?=/)' | sort -V | tail -1)
    fi
    
    # If both fail, use default
    if [ -z "$latest_major" ]; then
        echo "Failed to detect MediaWiki major version, using default" >&2
        latest_major="1.43"
    fi
    
    echo "Latest major version: $latest_major" >&2
    
    # Try to fetch full version with curl
    local latest_full=$(curl -s --connect-timeout 10 "https://releases.wikimedia.org/mediawiki/$latest_major/" | grep -oP '(?<=href=")mediawiki-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' | sort -V | tail -1 | sed 's/mediawiki-//;s/\.tar\.gz//')
    
    # If curl fails, try wget
    if [ -z "$latest_full" ]; then
        echo "Curl failed for full version, trying wget..." >&2
        latest_full=$(wget -qO- "https://releases.wikimedia.org/mediawiki/$latest_major/" 2>/dev/null | grep -oP '(?<=href=")mediawiki-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' | sort -V | tail -1 | sed 's/mediawiki-//;s/\.tar\.gz//')
    fi
    
    # If both fail, construct a version using major and .0
    if [ -z "$latest_full" ]; then
        echo "Failed to detect MediaWiki full version, constructing from major version" >&2
        latest_full="${latest_major}.0"
    fi
    
    # Return both major and full version
    echo "${latest_major}:${latest_full}"
}

# Get latest PHP version
PHP_VERSION=$(get_latest_php_version)
echo "✅ Latest PHP version: $PHP_VERSION"

# Get both MediaWiki versions at once and split them
MEDIAWIKI_VERSIONS=$(get_latest_mediawiki_version)
MEDIAWIKI_MAJOR_VERSION=$(echo "$MEDIAWIKI_VERSIONS" | cut -d':' -f1)
MEDIAWIKI_VERSION=$(echo "$MEDIAWIKI_VERSIONS" | cut -d':' -f2)
echo "✅ Latest MediaWiki version: $MEDIAWIKI_VERSION (major: $MEDIAWIKI_MAJOR_VERSION)"

# Output version information to a file if requested
if [ "$OUTPUT_VERSIONS" = "true" ]; then
    echo "Writing version information to version_info.env"
    cat > "$SCRIPT_DIR/version_info.env" << EOF
PHP_VERSION=$PHP_VERSION
MEDIAWIKI_VERSION=$MEDIAWIKI_VERSION
MEDIAWIKI_MAJOR_VERSION=$MEDIAWIKI_MAJOR_VERSION
EOF
fi

# Create build directory
BUILD_DIR="$SCRIPT_DIR/build"
mkdir -p "$BUILD_DIR"

# Create the healthcheck script separately to avoid quoting issues
HEALTHCHECK_PATH="$BUILD_DIR/healthcheck.sh"
cat > "$HEALTHCHECK_PATH" << 'EOF'
#!/bin/sh
set -e

# Check if nginx is running
if ! ps aux | grep -v grep | grep -q nginx; then
  echo "Health check failed: Nginx is not running"
  exit 1
fi

# Check if PHP-FPM is running
if ! ps aux | grep -v grep | grep -q php-fpm; then
  echo "Health check failed: PHP-FPM is not running"
  exit 1
fi

# Check if we can access the info.php page
if ! curl -s -f http://localhost/info.php | grep -q "PHP Version"; then
  echo "Health check failed: Cannot access PHP info page"
  exit 1
fi

# Check if we can ping localhost
if ! ping -c 1 localhost > /dev/null 2>&1; then
  echo "Health check failed: Cannot ping localhost"
  exit 1
fi

# Check if MediaWiki setup page is accessible
if curl -s http://localhost/mw-config/index.php?page=Welcome 2>/dev/null | grep -q "The environment has been checked"; then
  echo "MediaWiki setup page is accessible and environment check passed"
elif curl -s http://localhost/mw-config/index.php?page=Welcome 2>/dev/null | grep -q "cdx-message__content"; then
  echo "MediaWiki setup page is accessible"
else
  # Only warn, do not fail - the config might be complete already
  echo "Warning: MediaWiki setup page is not accessible, but this might be expected if already configured"
fi

echo "Health check passed"
exit 0
EOF
chmod +x "$HEALTHCHECK_PATH"

# Define Dockerfile path
DOCKERFILE_PATH="$BUILD_DIR/Dockerfile"

# Create a fresh Dockerfile directly
echo "📝 Generating Dockerfile..."
cat > "$DOCKERFILE_PATH" << EOF
FROM cgr.dev/chainguard/wolfi-base:latest

# Allow build-time customization of PHP version
ARG PHP_VERSION=8.4
ENV PHP_VERSION=\${PHP_VERSION}

# Allow build-time customization of MediaWiki version
ARG MEDIAWIKI_VERSION=1.43.0
ENV MEDIAWIKI_VERSION=\${MEDIAWIKI_VERSION}

# Accept the major version directly as a build arg
ARG MEDIAWIKI_MAJOR_VERSION=1.43
ENV MEDIAWIKI_MAJOR_VERSION=\${MEDIAWIKI_MAJOR_VERSION}

# Generate a list of required PHP extensions
RUN echo "Detected PHP version: \${PHP_VERSION}" && \\
    apk update && \\
    # Install base packages first
    apk add --no-cache \\
    nginx \\
    wget \\
    git \\
    diffutils \\
    ca-certificates \\
    shadow \\
    busybox \\
    imagemagick \\
    python3 \\
    curl \\
    # Install PHP and its extensions - try first with versioned format php-X.Y
    && (apk add --no-cache php-\${PHP_VERSION} php-\${PHP_VERSION}-fpm || true) \\
    # If the above fails, try with php-X.Y-X.Y.Z format
    && if ! command -v php > /dev/null; then \\
          echo "Trying alternative PHP package naming..."; \\
          # Find the actual package name for this version
          PHP_PKG=\$(apk search php | grep -E "^php-\${PHP_VERSION}-\${PHP_VERSION}" | sort -V | tail -1); \\
          if [ -n "\$PHP_PKG" ]; then \\
            echo "Found PHP package: \$PHP_PKG"; \\
            apk add --no-cache \$PHP_PKG; \\
          else \\
            echo "Could not find PHP package for version \${PHP_VERSION}"; \\
            exit 1; \\
          fi; \\
       fi \\
    # Now install required extensions - try both naming formats
    && for ext in fpm curl gd intl mbstring xml zip mysqli opcache calendar apcu mysqlnd ctype iconv fileinfo dom; do \\
         echo "Installing extension: \$ext"; \\
         apk add --no-cache php-\${PHP_VERSION}-\${ext} || \\
         apk add --no-cache \$(apk search php | grep -E "^php-\${PHP_VERSION}-\${ext}-[0-9]+" | sort -V | tail -1) || \\
         echo "Warning: Could not install PHP extension \$ext"; \\
       done

# Create both mediawiki and nginx users/groups
RUN groupadd -r mediawiki && \\
    useradd -r -g mediawiki -d /var/www/html -s /sbin/nologin mediawiki && \\
    groupadd -r nginx && \\
    useradd -r -g nginx -d /var/lib/nginx -s /sbin/nologin nginx

# Create necessary directories for Nginx
RUN mkdir -p /var/www/html /var/www/data /var/log/nginx /run/nginx \\
    /var/lib/nginx/tmp/client_body /var/lib/nginx/tmp/proxy \\
    /var/lib/nginx/tmp/fastcgi /var/lib/nginx/logs && \\
    chown -R mediawiki:mediawiki /var/www/html /var/www/data && \\
    chown -R nginx:nginx /var/log/nginx /run/nginx /var/lib/nginx

# Download and install MediaWiki
RUN wget "https://releases.wikimedia.org/mediawiki/\${MEDIAWIKI_MAJOR_VERSION}/mediawiki-\${MEDIAWIKI_VERSION}.tar.gz" -O /tmp/mediawiki.tar.gz && \\
    tar -xzf /tmp/mediawiki.tar.gz --strip-components=1 -C /var/www/html && \\
    rm /tmp/mediawiki.tar.gz && \\
    chown -R mediawiki:mediawiki /var/www/html

# Configure PHP
RUN mkdir -p /etc/php/\${PHP_VERSION}/conf.d && \\
    echo 'opcache.memory_consumption=128' >> /etc/php/\${PHP_VERSION}/conf.d/opcache-recommended.ini && \\
    echo 'opcache.interned_strings_buffer=8' >> /etc/php/\${PHP_VERSION}/conf.d/opcache-recommended.ini && \\
    echo 'opcache.max_accelerated_files=4000' >> /etc/php/\${PHP_VERSION}/conf.d/opcache-recommended.ini && \\
    echo 'opcache.revalidate_freq=60' >> /etc/php/\${PHP_VERSION}/conf.d/opcache-recommended.ini

# Create an extension directory for all PHP extensions to load them in the correct order
RUN mkdir -p /etc/php/\${PHP_VERSION}/conf.d/extensions && \\
    echo 'extension=mysqlnd.so' > /etc/php/\${PHP_VERSION}/conf.d/extensions/10-mysqlnd.ini && \\
    echo 'extension=mysqli.so' > /etc/php/\${PHP_VERSION}/conf.d/extensions/20-mysqli.ini && \\
    echo 'extension=calendar.so' > /etc/php/\${PHP_VERSION}/conf.d/extensions/20-calendar.ini && \\
    echo 'extension=apcu.so' > /etc/php/\${PHP_VERSION}/conf.d/extensions/20-apcu.ini && \\
    echo 'extension=ctype.so' > /etc/php/\${PHP_VERSION}/conf.d/extensions/20-ctype.ini && \\
    echo 'extension=iconv.so' > /etc/php/\${PHP_VERSION}/conf.d/extensions/20-iconv.ini && \\
    echo 'extension=fileinfo.so' > /etc/php/\${PHP_VERSION}/conf.d/extensions/20-fileinfo.ini && \\
    echo 'extension=dom.so' > /etc/php/\${PHP_VERSION}/conf.d/extensions/20-dom.ini

# Remove any default nginx configurations that might be causing conflicts
RUN rm -f /etc/nginx/nginx.conf /etc/nginx/conf.d/*.conf 2>/dev/null || true

# Create nginx.conf with nginx user explicitly specified and security headers
RUN echo 'user nginx nginx;' > /etc/nginx/nginx.conf && \\
    echo 'worker_processes auto;' >> /etc/nginx/nginx.conf && \\
    echo 'pid /run/nginx/nginx.pid;' >> /etc/nginx/nginx.conf && \\
    echo 'events {' >> /etc/nginx/nginx.conf && \\
    echo '    worker_connections 768;' >> /etc/nginx/nginx.conf && \\
    echo '}' >> /etc/nginx/nginx.conf && \\
    echo 'http {' >> /etc/nginx/nginx.conf && \\
    echo '    sendfile on;' >> /etc/nginx/nginx.conf && \\
    echo '    tcp_nopush on;' >> /etc/nginx/nginx.conf && \\
    echo '    tcp_nodelay on;' >> /etc/nginx/nginx.conf && \\
    echo '    keepalive_timeout 65;' >> /etc/nginx/nginx.conf && \\
    echo '    types_hash_max_size 2048;' >> /etc/nginx/nginx.conf && \\
    echo '    include /etc/nginx/mime.types;' >> /etc/nginx/nginx.conf && \\
    echo '    default_type application/octet-stream;' >> /etc/nginx/nginx.conf && \\
    echo '    server {' >> /etc/nginx/nginx.conf && \\
    echo '        listen 80;' >> /etc/nginx/nginx.conf && \\
    echo '        root /var/www/html;' >> /etc/nginx/nginx.conf && \\
    echo '        index index.php;' >> /etc/nginx/nginx.conf && \\
    echo '        server_name _;' >> /etc/nginx/nginx.conf && \\
    echo '        location / {' >> /etc/nginx/nginx.conf && \\
    echo '            try_files \$uri \$uri/ /index.php?\$args;' >> /etc/nginx/nginx.conf && \\
    echo '        }' >> /etc/nginx/nginx.conf && \\
    echo '        location ~ \\.php$ {' >> /etc/nginx/nginx.conf && \\
    echo '            include fastcgi_params;' >> /etc/nginx/nginx.conf && \\
    echo '            fastcgi_pass 127.0.0.1:9000;' >> /etc/nginx/nginx.conf && \\
    echo '            fastcgi_index index.php;' >> /etc/nginx/nginx.conf && \\
    echo '            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;' >> /etc/nginx/nginx.conf && \\
    echo '        }' >> /etc/nginx/nginx.conf && \\
    echo '        # Security headers for uploads' >> /etc/nginx/nginx.conf && \\
    echo '        location /images/ {' >> /etc/nginx/nginx.conf && \\
    echo '            add_header X-Content-Type-Options "nosniff" always;' >> /etc/nginx/nginx.conf && \\
    echo '            # Disable PHP execution in uploads directory' >> /etc/nginx/nginx.conf && \\
    echo '            location ~ \\.php$ {' >> /etc/nginx/nginx.conf && \\
    echo '                deny all;' >> /etc/nginx/nginx.conf && \\
    echo '            }' >> /etc/nginx/nginx.conf && \\
    echo '        }' >> /etc/nginx/nginx.conf && \\
    echo '    }' >> /etc/nginx/nginx.conf && \\
    echo '}' >> /etc/nginx/nginx.conf

# Create a basic fastcgi_params file if it doesn't exist
RUN echo 'fastcgi_param  QUERY_STRING       \$query_string;' > /etc/nginx/fastcgi_params && \\
    echo 'fastcgi_param  REQUEST_METHOD     \$request_method;' >> /etc/nginx/fastcgi_params && \\
    echo 'fastcgi_param  CONTENT_TYPE       \$content_type;' >> /etc/nginx/fastcgi_params && \\
    echo 'fastcgi_param  CONTENT_LENGTH     \$content_length;' >> /etc/nginx/fastcgi_params && \\
    echo 'fastcgi_param  SCRIPT_NAME        \$fastcgi_script_name;' >> /etc/nginx/fastcgi_params && \\
    echo 'fastcgi_param  REQUEST_URI        \$request_uri;' >> /etc/nginx/fastcgi_params && \\
    echo 'fastcgi_param  DOCUMENT_URI       \$document_uri;' >> /etc/nginx/fastcgi_params && \\
    echo 'fastcgi_param  DOCUMENT_ROOT      \$document_root;' >> /etc/nginx/fastcgi_params && \\
    echo 'fastcgi_param  SERVER_PROTOCOL    \$server_protocol;' >> /etc/nginx/fastcgi_params && \\
    echo 'fastcgi_param  GATEWAY_INTERFACE  CGI/1.1;' >> /etc/nginx/fastcgi_params && \\
    echo 'fastcgi_param  SERVER_SOFTWARE    nginx/\$nginx_version;' >> /etc/nginx/fastcgi_params && \\
    echo 'fastcgi_param  REMOTE_ADDR        \$remote_addr;' >> /etc/nginx/fastcgi_params && \\
    echo 'fastcgi_param  REMOTE_PORT        \$remote_port;' >> /etc/nginx/fastcgi_params && \\
    echo 'fastcgi_param  SERVER_ADDR        \$server_addr;' >> /etc/nginx/fastcgi_params && \\
    echo 'fastcgi_param  SERVER_PORT        \$server_port;' >> /etc/nginx/fastcgi_params && \\
    echo 'fastcgi_param  SERVER_NAME        \$server_name;' >> /etc/nginx/fastcgi_params

# Make web files accessible to nginx user
RUN chmod -R 755 /var/www/html && \\
    chown -R mediawiki:mediawiki /var/www/html && \\
    chmod -R g+r /var/www/html && \\
    usermod -a -G mediawiki nginx

# Create uploads directory and set permissions
RUN mkdir -p /var/www/html/images/tmp /var/www/html/images/thumb && \\
    chown -R mediawiki:mediawiki /var/www/html/images && \\
    chmod -R 755 /var/www/html/images

# Create a basic PHP info page for testing
RUN echo "<?php phpinfo(); ?>" > /var/www/html/info.php && \\
    chown mediawiki:mediawiki /var/www/html/info.php

# Copy in the pre-created healthcheck script
COPY healthcheck.sh /healthcheck.sh
RUN chmod +x /healthcheck.sh

# Create entrypoint script with correct PHP-FPM configuration for Wolfi
RUN echo '#!/bin/sh' > /entrypoint.sh && \\
    echo 'set -e' >> /entrypoint.sh && \\
    echo '' >> /entrypoint.sh && \\
    echo '# Configure PHP-FPM to run as mediawiki user' >> /entrypoint.sh && \\
    echo 'mkdir -p /run/php-fpm' >> /entrypoint.sh && \\
    echo '' >> /entrypoint.sh && \\
    echo '# Create PHP-FPM pool configuration' >> /entrypoint.sh && \\
    echo "mkdir -p /etc/php/\${PHP_VERSION}/php-fpm.d/" >> /entrypoint.sh && \\
    echo "echo \"[www]\" > /etc/php/\${PHP_VERSION}/php-fpm.d/www.conf" >> /entrypoint.sh && \\
    echo "echo \"user = mediawiki\" >> /etc/php/\${PHP_VERSION}/php-fpm.d/www.conf" >> /entrypoint.sh && \\
    echo "echo \"group = mediawiki\" >> /etc/php/\${PHP_VERSION}/php-fpm.d/www.conf" >> /entrypoint.sh && \\
    echo "echo \"listen = 127.0.0.1:9000\" >> /etc/php/\${PHP_VERSION}/php-fpm.d/www.conf" >> /entrypoint.sh && \\
    echo "echo \"pm = dynamic\" >> /etc/php/\${PHP_VERSION}/php-fpm.d/www.conf" >> /entrypoint.sh && \\
    echo "echo \"pm.max_children = 5\" >> /etc/php/\${PHP_VERSION}/php-fpm.d/www.conf" >> /entrypoint.sh && \\
    echo "echo \"pm.start_servers = 2\" >> /etc/php/\${PHP_VERSION}/php-fpm.d/www.conf" >> /entrypoint.sh && \\
    echo "echo \"pm.min_spare_servers = 1\" >> /etc/php/\${PHP_VERSION}/php-fpm.d/www.conf" >> /entrypoint.sh && \\
    echo "echo \"pm.max_spare_servers = 3\" >> /etc/php/\${PHP_VERSION}/php-fpm.d/www.conf" >> /entrypoint.sh && \\
    echo '' >> /entrypoint.sh && \\
    echo '# Find PHP-FPM executable' >> /entrypoint.sh && \\
    echo 'echo "Looking for PHP-FPM executable..."' >> /entrypoint.sh && \\
    echo "if [ -x \"/usr/bin/php-fpm\${PHP_VERSION}\" ]; then" >> /entrypoint.sh && \\
    echo "  PHP_FPM_BIN=\"/usr/bin/php-fpm\${PHP_VERSION}\"" >> /entrypoint.sh && \\
    echo 'elif [ -x "/usr/bin/php-fpm" ]; then' >> /entrypoint.sh && \\
    echo '  PHP_FPM_BIN="/usr/bin/php-fpm"' >> /entrypoint.sh && \\
    echo "elif [ -x \"/usr/sbin/php-fpm\${PHP_VERSION}\" ]; then" >> /entrypoint.sh && \\
    echo "  PHP_FPM_BIN=\"/usr/sbin/php-fpm\${PHP_VERSION}\"" >> /entrypoint.sh && \\
    echo 'elif [ -x "/usr/sbin/php-fpm" ]; then' >> /entrypoint.sh && \\
    echo '  PHP_FPM_BIN="/usr/sbin/php-fpm"' >> /entrypoint.sh && \\
    echo 'else' >> /entrypoint.sh && \\
    echo '  echo "PHP-FPM executable not found. Attempting to find it..."' >> /entrypoint.sh && \\
    echo '  PHP_FPM_BIN=\$(find /usr -name "php-fpm*" -type f -executable | grep -v "\.conf" | head -1)' >> /entrypoint.sh && \\
    echo '  if [ -z "\$PHP_FPM_BIN" ]; then' >> /entrypoint.sh && \\
    echo '    echo "Error: PHP-FPM executable could not be found"' >> /entrypoint.sh && \\
    echo '    exit 1' >> /entrypoint.sh && \\
    echo '  fi' >> /entrypoint.sh && \\
    echo 'fi' >> /entrypoint.sh && \\
    echo 'echo "Found PHP-FPM at: \$PHP_FPM_BIN"' >> /entrypoint.sh && \\
    echo '' >> /entrypoint.sh && \\
    echo 'echo "Starting PHP-FPM with user: mediawiki"' >> /entrypoint.sh && \\
    echo "CONF_PATH=\"/etc/php/\${PHP_VERSION}/php-fpm.d/www.conf\"" >> /entrypoint.sh && \\
    echo '\$PHP_FPM_BIN --nodaemonize --fpm-config \$CONF_PATH &' >> /entrypoint.sh && \\
    echo '' >> /entrypoint.sh && \\
    echo 'echo "Starting Nginx with user: nginx"' >> /entrypoint.sh && \\
    echo 'nginx -g "daemon off;"' >> /entrypoint.sh && \\
    chmod +x /entrypoint.sh

# Add health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \\
    CMD /healthcheck.sh

# Expose port for web access
EXPOSE 80

# Set working directory
WORKDIR /var/www/html

# Run entrypoint
ENTRYPOINT ["/entrypoint.sh"]
EOF

echo "📋 Created new Dockerfile at $DOCKERFILE_PATH"

# Image tag 
IMAGE_TAG="wolfi-mediawiki:$MEDIAWIKI_VERSION"
LATEST_TAG="wolfi-mediawiki:latest"
MAJOR_TAG="wolfi-mediawiki:$MEDIAWIKI_MAJOR_VERSION"

# Build the Docker image
echo "🔨 Building Docker image with PHP $PHP_VERSION and MediaWiki $MEDIAWIKI_VERSION..."
docker build \
    --build-arg PHP_VERSION=$PHP_VERSION \
    --build-arg MEDIAWIKI_VERSION=$MEDIAWIKI_VERSION \
    --build-arg MEDIAWIKI_MAJOR_VERSION=$MEDIAWIKI_MAJOR_VERSION \
    -t $IMAGE_TAG \
    -f "$DOCKERFILE_PATH" \
    "$BUILD_DIR"

echo "📦 Built image: $IMAGE_TAG"

# Also tag as latest and major version
docker tag $IMAGE_TAG $LATEST_TAG
docker tag $IMAGE_TAG $MAJOR_TAG
echo "🏷️ Tagged as $LATEST_TAG"
echo "🏷️ Tagged as $MAJOR_TAG"

# Run the container
echo "🚀 Running container for testing..."
CONTAINER_ID=$(docker run -d -p 8080:80 $IMAGE_TAG)
echo "Container ID: $CONTAINER_ID"

# Cleanup function
cleanup() {
    echo "🧹 Cleaning up..."
    docker rm -f $CONTAINER_ID >/dev/null 2>&1 || true
}

# Set trap for cleanup
trap cleanup EXIT

# Ping test function
ping_test() {
    local max_attempts=10
    local attempt=1
    
    echo "🔄 Testing container ping..."
    while [ $attempt -le $max_attempts ]; do
        echo "  Attempt $attempt of $max_attempts"
        
        if docker exec $CONTAINER_ID ping -c 1 localhost >/dev/null 2>&1; then
            echo "✅ Ping test successful"
            return 0
        fi
        
        sleep 3
        attempt=$((attempt + 1))
    done
    
    echo "❌ Ping test failed after $max_attempts attempts"
    docker logs $CONTAINER_ID
    return 1
}

# Wait for container to start and become healthy
health_check() {
    local max_attempts=20
    local attempt=1
    
    echo "🔄 Waiting for container to become healthy..."
    while [ $attempt -le $max_attempts ]; do
        echo "  Health check attempt $attempt of $max_attempts"
        
        # Check if container is still running
        if [ "$(docker inspect -f {{.State.Running}} $CONTAINER_ID 2>/dev/null)" != "true" ]; then
            echo "❌ Container failed to start or crashed"
            docker logs $CONTAINER_ID
            return 1
        fi
        
        # Get container health status
        local health_status=$(docker inspect -f '{{.State.Health.Status}}' $CONTAINER_ID 2>/dev/null)
        
        if [ "$health_status" = "healthy" ]; then
            echo "✅ Container is healthy!"
            return 0
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            echo "❌ Container never became healthy within the allotted time"
            docker logs $CONTAINER_ID
            return 1
        fi
        
        sleep 5
        attempt=$((attempt + 1))
    done
    
    return 1
}

# Check MediaWiki setup page
check_mediawiki_setup() {
    local max_attempts=20
    local attempt=1
    
    echo "🔄 Checking MediaWiki setup page..."
    while [ $attempt -le $max_attempts ]; do
        echo "  Attempt $attempt of $max_attempts"
        
        # Try regular setup page first
        local setup_response=$(curl -s --max-time 5 http://localhost:8080/mw-config/index.php?page=Welcome)
        
        # Check for expected content - don't output the full response to avoid broken pipe
        if echo "$setup_response" | grep -q "The environment has been checked"; then
            echo "✅ MediaWiki environment check successful"
            return 0
        elif echo "$setup_response" | grep -q "cdx-message__content"; then
            echo "✅ MediaWiki page loaded, configuration page detected"
            return 0
        fi
        
        # Also check if MainPage is accessible (in case MediaWiki is already set up)
        if curl -s --max-time 5 http://localhost:8080/index.php/Main_Page | grep -q "MediaWiki"; then
            echo "✅ MediaWiki Main Page is accessible"
            return 0
        fi
        
        # Check if the PHP info page is at least accessible
        if curl -s --max-time 5 http://localhost:8080/info.php | grep -q "PHP Version"; then
            echo "ℹ️ PHP info page is accessible, waiting for MediaWiki setup..."
        else
            echo "⚠️ PHP info page is not accessible yet"
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            echo "❌ MediaWiki setup check failed after $max_attempts attempts"
            
            # Don't try to print the entire response, just check if we got anything
            if [ -n "$setup_response" ]; then
                echo "Got a response from the server, but it doesn't match expected patterns"
            else
                echo "No response from the setup page"
            fi
            
            # Check if any web server is responding
            if curl -s --max-time 5 http://localhost:8080/ > /dev/null; then
                echo "✓ Web server is responding at http://localhost:8080/"
            else
                echo "✗ Web server is not responding at http://localhost:8080/"
            fi
            
            # Check container logs - limited output to avoid pipe issues
            echo "Container logs (last 20 lines):"
            docker logs $CONTAINER_ID | tail -n 20
            
            return 1
        fi
        
        sleep 5
        attempt=$((attempt + 1))
    done
    
    return 1
}

# Run tests - always run tests, don't skip
echo "🧪 Running tests..."
TESTS_PASSED=true

if ! ping_test; then
    TESTS_PASSED=false
fi

if ! health_check; then
    TESTS_PASSED=false
fi

if ! check_mediawiki_setup; then
    TESTS_PASSED=false
fi

# Final test result
if [ "$TESTS_PASSED" = "false" ]; then
    echo "❌ One or more tests failed. Not pushing to Docker Hub."
    exit 1
fi

echo "✅ All tests passed!"

# If we have Docker Hub credentials and auto-push is enabled, push to Docker Hub
if [ "$AUTO_PUSH" = "true" ]; then
    if [ -z "$DOCKERHUB_USERNAME" ] || [ -z "$DOCKERHUB_TOKEN" ]; then
        echo "⚠️ Docker Hub credentials not provided. Not pushing to Docker Hub."
    else
        echo "🔐 Logging in to Docker Hub..."
        echo "$DOCKERHUB_TOKEN" | docker login --username "$DOCKERHUB_USERNAME" --password-stdin

        # Prepare Docker Hub image tags
        DOCKERHUB_IMAGE_VERSION="$DOCKERHUB_USERNAME/wolfi-mediawiki:$MEDIAWIKI_VERSION"
        DOCKERHUB_IMAGE_MAJOR="$DOCKERHUB_USERNAME/wolfi-mediawiki:$MEDIAWIKI_MAJOR_VERSION"
        DOCKERHUB_IMAGE_LATEST="$DOCKERHUB_USERNAME/wolfi-mediawiki:latest"

        # Tag for Docker Hub
        docker tag $IMAGE_TAG $DOCKERHUB_IMAGE_VERSION
        docker tag $IMAGE_TAG $DOCKERHUB_IMAGE_MAJOR
        docker tag $IMAGE_TAG $DOCKERHUB_IMAGE_LATEST

        # Push to Docker Hub
        echo "📤 Pushing to Docker Hub..."
        docker push $DOCKERHUB_IMAGE_VERSION
        docker push $DOCKERHUB_IMAGE_MAJOR
        docker push $DOCKERHUB_IMAGE_LATEST

        echo "✅ Image pushed to Docker Hub with tags:"
        echo "   - $DOCKERHUB_IMAGE_VERSION"
        echo "   - $DOCKERHUB_IMAGE_MAJOR"
        echo "   - $DOCKERHUB_IMAGE_LATEST"
    fi
else
    echo "ℹ️ Auto-push is disabled. Skipping push to Docker Hub."
    echo "   To enable auto-push, use --auto-push flag or provide Docker Hub credentials."
fi

echo "✨ Build process completed successfully!"