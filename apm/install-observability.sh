#!/bin/bash

set -e

echo "🔍 Detectando versão do PHP..."

if ! command -v php &> /dev/null; then
  echo "❌ PHP não está instalado."
  exit 1
fi

if ! command -v composer &> /dev/null; then
  echo "❌ Composer não está instalado."
  exit 1
fi

PHP_VERSION=$(php -r 'echo PHP_VERSION;')
PHP_MAJOR=$(php -r 'echo PHP_MAJOR_VERSION;')
PHP_MINOR=$(php -r 'echo PHP_MINOR_VERSION;')

echo "✅ PHP detectado: $PHP_VERSION"

install_opentelemetry() {
  echo "🚀 Instalando..."

  pecl install opentelemetry

  echo "✅ Habilitando extensão"
  echo "extension=opentelemetry.so" > /usr/local/etc/php/conf.d/99-opentelemetry.ini

  echo "📦 Instalando dependências Composer"
  composer require \
    open-telemetry/sdk \
    open-telemetry/exporter-otlp \
    open-telemetry/opentelemetry-auto-psr18 \
    open-telemetry/opentelemetry-auto-slim
}

install_ddtrace() {
  echo "🚀 Instalando..."

  curl -sSL https://github.com/DataDog/dd-trace-php/releases/latest/download/datadog-setup.php -o /tmp/datadog-setup.php
  php /tmp/datadog-setup.php --php-bin php --enable
  rm /tmp/datadog-setup.php

  echo "✅ Configurando"
  CONF_FILE="/usr/local/etc/php/conf.d/ddtrace.ini"

  echo "ddtrace.request_init_hook=/opt/datadog-php/dd-trace-sources/bridge/dd_wrap_autoloader.php" >> "$CONF_FILE"
  echo "ddtrace.ignore_routes='healthcheck,ping'" >> "$CONF_FILE"
  echo "ddtrace.tags=env:prod,team:asa" >> "$CONF_FILE"
  echo "ddtrace.log_level=debug" >> "$CONF_FILE"
  echo "ddtrace.trace_agent_url=http://otel-collector:4318/v1/traces" >> "$CONF_FILE"
}

if [ "$PHP_MAJOR" -eq 8 ]; then
  install_opentelemetry
elif [ "$PHP_MAJOR" -eq 7 ]; then
  if [ "$PHP_MINOR" -ge 0 ]; then
    install_ddtrace
  else
    echo "❌ Versão do PHP não suportada."
    exit 1
  fi
else
  echo "❌ Versão do PHP não suportada."
  exit 1
fi

echo "✅ Instalação finalizada com sucesso!"
