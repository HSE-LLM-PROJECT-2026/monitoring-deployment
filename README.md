# Monitoring Deployment

## Описание

Набор конфигов и скриптов мониторинга платформы: Prometheus/Grafana/Loki, дашборды по inference, релизам, квотам, затратам и инфраструктуре.

## Основные возможности

- готовые Grafana dashboards для platform компонентов
- probes и service monitors
- вспомогательные скрипты для alerting/UPS/NUT сценариев

## Структура проекта

- `dashboards/` - json-дашборды
- `scripts/` - скрипты применения и обслуживания
- `probes/`, `servicemonitors/`, `prometheus-rules/` - мониторинг манифесты

## Запуск

- базовый rollout: `rebuild-delete-deploy.sh`
- обновление параметров: `apply-new-variables.sh`
