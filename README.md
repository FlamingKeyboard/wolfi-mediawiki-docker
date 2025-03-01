# Wolfi MediaWiki Docker Image

This repository contains a Dockerfile for running MediaWiki 1.43.0 on Wolfi Linux, a minimal, container-optimized Linux distribution focused on security.

## Features

- Based on the lightweight `cgr.dev/chainguard/wolfi-base` image
- Uses PHP 8.4 with FPM and Nginx instead of Apache
- Includes all necessary PHP extensions for MediaWiki
- Properly configured security headers for upload directory
- Follows security best practices for running MediaWiki in containers

## Quick Start

```bash
# Build the image
docker build -t wolfi-mediawiki .

# Run the container
docker run -d -p 80:80 --name wolfi-mediawiki wolfi-mediawiki

# Access MediaWiki at http://localhost
```

## Environment Variables

No environment variables are currently supported. The container is configured to run MediaWiki out of the box.

## Volumes

For production use, you should mount volumes for:

- `/var/www/html/images` - For uploaded files
- `/var/www/html/LocalSettings.php` - After initial setup

Example with volumes:

```bash
docker run -d -p 80:80 \
  -v mediawiki-images:/var/www/html/images \
  -v /path/to/LocalSettings.php:/var/www/html/LocalSettings.php \
  --name wolfi-mediawiki wolfi-mediawiki
```

## Docker Compose Example

```yaml
version: '3'
services:
  mediawiki:
    build: .
    restart: always
    ports:
      - 8080:80
    links:
      - database
    volumes:
      - images:/var/www/html/images
      # After initial setup, download LocalSettings.php and add this line:
      # - ./LocalSettings.php:/var/www/html/LocalSettings.php

  database:
    image: mariadb
    restart: always
    environment:
      MYSQL_DATABASE: my_wiki
      MYSQL_USER: wikiuser
      MYSQL_PASSWORD: example
      MYSQL_RANDOM_ROOT_PASSWORD: 'yes'
    volumes:
      - db:/var/lib/mysql

volumes:
  images:
  db:
```

## Initial Setup

When you first access the MediaWiki instance, you'll need to go through the setup process:

1. Visit http://localhost or http://localhost:8080 (depending on your port mapping)
2. Follow the installation wizard
3. When asked for database settings, use the following values (if using the Docker Compose example):
   - Database type: MySQL, MariaDB, or equivalent
   - Database host: database
   - Database name: my_wiki
   - Database username: wikiuser
   - Database password: example
4. Complete the installation
5. Download the generated `LocalSettings.php` file
6. Place the file in your container or mount it as a volume

## Security Features

This container includes several security features:

- X-Content-Type-Options: nosniff header for uploads directory
- PHP execution is disabled in the uploads directory
- Proper file permissions for MediaWiki directories
- Separate nginx and MediaWiki users for privilege separation

## Differences from Official MediaWiki Image

- Based on Wolfi Linux instead of Debian/Alpine
- Uses Nginx + PHP-FPM instead of Apache
- More security features out of the box
- PHP 8.4 instead of older PHP versions

## License

This Dockerfile and associated scripts are provided under the same license as MediaWiki itself (GPL-2.0+).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Issues

Please file issues on GitHub with details about what you're experiencing.