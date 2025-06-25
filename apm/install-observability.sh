#!/bin/bash

set -e

echo "🔍 Detectando sistema operacional..."

# Detectar gerenciador de pacotes
if command -v apt-get &> /dev/null; then
  PM_INSTALL="apt-get install -y"
  PM_UPDATE="apt-get update -y"
elif command -v yum &> /dev/null; then
  PM_INSTALL="yum install -y"
  PM_UPDATE="yum update -y"
elif command -v apk &> /dev/null; then
  PM_INSTALL="apk add --no-cache"
  PM_UPDATE="apk update"
else
  echo "❌ Gerenciador de pacotes não suportado."
  exit 1
fi

echo "✅ Instalando pacotes necessários..."
$PM_UPDATE

# Instalar apenas o que não está incluso na imagem php:8.x
$PM_INSTALL git unzip autoconf build-essential pkg-config curl gcc make

# Composer já instalado?
if ! command -v composer &> /dev/null; then
  echo "📦 Instalando Composer..."
  curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
fi

echo "🔍 Detectando versão do PHP..."

if ! command -v php &> /dev/null; then
  echo "❌ PHP não está instalado."
  exit 1
fi

PHP_VERSION=$(php -r 'echo PHP_VERSION;')
PHP_MAJOR=$(php -r 'echo PHP_MAJOR_VERSION;')
PHP_MINOR=$(php -r 'echo PHP_MINOR_VERSION;')

echo "✅ PHP detectado: $PHP_VERSION"

install_opentelemetry_pecl() {
  echo "📦 Instalando OpenTelemetry via PECL..."
  yes '' | pecl install opentelemetry
  echo "extension=opentelemetry.so" > /usr/local/etc/php/conf.d/99-opentelemetry.ini
}

install_opentelemetry_git() {
  echo "📦 Instalando OpenTelemetry via Git (build manual)..."
  git clone https://github.com/open-telemetry/opentelemetry-php-instrumentation.git /tmp/otel-php \
    && cd /tmp/otel-php/ext \
    && phpize \
    && ./configure \
    && make \
    && make install \
    && echo "extension=opentelemetry.so" > /usr/local/etc/php/conf.d/99-opentelemetry.ini \
    && rm -rf /tmp/otel-php
}

install_opentelemetry_composer_packages() {
  echo "📦 Instalando dependências do OpenTelemetry via Composer..."
  composer require \
    open-telemetry/sdk \
    open-telemetry/exporter-otlp \
    open-telemetry/opentelemetry-auto-psr18 \
    open-telemetry/opentelemetry-auto-slim
}

install_trace_legacy() {
  echo "📦 Instalando biblioteca de rastreamento para ambientes PHP 7.x..."
  curl -sSL https://github.com/DataDog/dd-trace-php/releases/latest/download/datadog-setup.php -o /tmp/datadog-setup.php
  php /tmp/datadog-setup.php --php-bin php --enable
  rm /tmp/datadog-setup.php

  echo "✅ Configurando rastreamento (PHP 7.x)"
  CONF_FILE="/usr/local/etc/php/conf.d/ddtrace.ini"
  echo "ddtrace.request_init_hook=/opt/datadog-php/dd-trace-sources/bridge/dd_wrap_autoloader.php" >> "$CONF_FILE"
  echo "ddtrace.ignore_routes='healthcheck,ping'" >> "$CONF_FILE"
  echo "ddtrace.tags=env:prod,team:asa" >> "$CONF_FILE"
  echo "ddtrace.log_level=debug" >> "$CONF_FILE"
  echo "ddtrace.trace_agent_url=http://otel-collector:4318/v1/traces" >> "$CONF_FILE"
}

# Decisão com base na versão do PHP
if [ "$PHP_MAJOR" -eq 8 ]; then
  if [ "$PHP_MINOR" -le 2 ]; then
    install_opentelemetry_pecl
  else
    install_opentelemetry_git
  fi
  install_opentelemetry_composer_packages
elif [ "$PHP_MAJOR" -eq 7 ]; then
  install_trace_legacy
else
  echo "❌ Versão do PHP não suportada para rastreamento automático."
  exit 1
fi

echo "✅ Instalação finalizada com sucesso!"
