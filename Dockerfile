FROM php:7.2-cli

# Install and configure PHP dependencies and extensions.
RUN set -ex; \
  # Save apt-mark's 'manual' list for purging build dependencies.
  savedAptMark="$(apt-mark showmanual)"; \
  \
  # Install build dependencies.
  apt-get update; \
  apt-get install -y --no-install-recommends \
    libjpeg-dev \
    libpng-dev \
    libpq-dev \
    zlib1g-dev \
  ; \
  # Extract the PHP source and configure extensions.
  docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr; \
  \
  docker-php-ext-install -j "$(nproc)" \
    exif \
    gd \
    mbstring \
    mysqli \
    opcache \
    pdo \
    pdo_mysql \
    zip \
  ; \
  \
  # Reset apt-mark's 'manual' list so that 'purge --auto-remove' will remove all
  # build dependencies.
  apt-mark auto '.*' > /dev/null; \
  apt-mark manual $savedAptMark; \
  ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
    | awk '/=>/ { print $3 }' \
    | sort -u \
    | xargs -r dpkg-query -S \
    | cut -d: -f1 \
    | sort -u \
    | xargs -rt apt-mark manual; \
  \
  apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
  rm -rf /var/lib/apt/lists/*

RUN set -ex; \
  { \
    # Set recommended PHP.ini settings.
    # See https://secure.php.net/manual/en/opcache.installation.php.
    echo 'opcache.memory_consumption = 128'; \
    echo 'opcache.interned_strings_buffer = 8'; \
    echo 'opcache.max_accelerated_files = 4000'; \
    echo 'opcache.revalidate_freq = 60'; \
    echo 'opcache.fast_shutdown = 1'; \
    echo 'opcache.enable_cli = 1'; \
  } > /usr/local/etc/php/conf.d/opcache-recommended.ini

# Install ImageMagick dependencies and ImageMagick.
RUN set -ex; \
  \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    libmagickwand-dev \
    imagemagick \
  ; \
  rm -rf /var/lib/apt/lists/*

# Install Drupal Console Launcher, Drush Launcher and dependencies.
RUN set -ex; \
  \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    default-mysql-client \
    rsync \
  ; \
  rm -rf /var/lib/apt/lists/*; \
  \
  curl -OL https://github.com/drush-ops/drush-launcher/releases/download/0.6.0/drush.phar; \
  chmod +x drush.phar; \
  mv drush.phar /usr/local/bin/drush; \
  \
  curl https://drupalconsole.com/installer -L -o drupal.phar; \
  mv drupal.phar /usr/local/bin/drupal; \
  chmod +x /usr/local/bin/drupal

# Install cron.
RUN set -ex; \
  \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    cron \
  ; \
  rm -rf /var/lib/apt/lists/*; \
  # Add a cron job for Drupal.
  { \
    echo 'SHELL=/bin/bash'; \
    echo "PATH=$PATH"; \
    echo '* * * * * root drush -r /var/www cron > /var/log/cron.log 2>&1'; \
    echo ''; \
  } > /etc/cron.d/drupal; \
  # Redirect logs to stdout.
  ln -sfT /proc/1/fd/1 /var/log/cron.log

WORKDIR /var/www

# Set cron as the default command.
CMD ["cron", "-f"]

HEALTHCHECK --interval=5m --timeout=3s \
  CMD drush -r /var/www/html status bootstrap | grep -q Successful
