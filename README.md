# Monitoring Deployment

[HSE-LLM-PROJECT-2026/monitoring-deployment](https://github.com/HSE-LLM-PROJECT-2026/monitoring-deployment)

## Описание

Репозиторий мониторинга платформы. В нем лежит раскатка Prometheus/Grafana/Loki/Alertmanager, ServiceMonitor-ы, Grafana dashboards, Tuya power exporter и UPS monitoring.

## Основные возможности

- kube-prometheus-stack
- Grafana dashboards для платформы, GPU, vLLM, backend и стоимости
- Loki/Promtail для логов
- blackbox exporter для health checks
- dcgm-exporter для GPU metrics
- postgres exporter
- Tuya exporter для мониторинга энергопотребления
- NUT UPS exporter и email alerts

## Структура проекта

- `dashboards/` — JSON-дашборды Grafana
- `servicemonitors/` — ServiceMonitor manifests
- `prometheus-rules/` — alert rules
- `alertmanagerconfigs/` — Alertmanager routing
- `tuya-exporter/` — exporter розетки/энергии
- `ups-exporter/` — exporter UPS
- `probes/` — blackbox probes
- `values.*.yaml` — Helm values для компонентов
- `common.sh`, `deploy-from-scratch.sh`, `rebuild-delete-deploy.sh` — deploy scripts

## Деплой

```bash
./deploy-from-scratch.sh
```

Пересборка и переустановка:

```bash
./rebuild-delete-deploy.sh
```

Применить dashboards отдельно:

```bash
./apply-dashboards.sh
```

## Секреты

Секреты для Resend, Tuya и UPS создаются отдельными скриптами:

```bash
./create-resend-secret.sh
./create-tuya-secret.sh
./create-ups-secret.sh
```

Реальные значения секретов в репозиторий не коммитятся.

## Автор

Igor Malysh
