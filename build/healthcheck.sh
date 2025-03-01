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
