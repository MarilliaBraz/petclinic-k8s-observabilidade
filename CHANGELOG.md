# Changelog

Todas as mudanças relevantes deste repositório. O formato segue o
[Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e as versões seguem o
[Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [1.0.0] - 2026-11-19

### Adicionado

- Imagem do Spring PetClinic construída a partir do código oficial, fixada no commit `500158f`.
- PostgreSQL 17.12 em StatefulSet com volume persistente e três contas separadas (administração, aplicação e monitoramento).
- PetClinic com 2 réplicas ligadas ao banco pelo `banco-service`, exposto pelo `app-service` (NodePort 30080).
- Instrumentação automática com o agente Java do OpenTelemetry 2.33.1, injetado por initContainer.
- Stack de observabilidade instalada com Helm: kube-prometheus-stack 93.4.1, Loki 21.4.1, Tempo 3.2.1, OpenTelemetry Collector 0.180.0 e postgres-exporter 8.3.0.
- Painel do Grafana com métricas, logs e traces da aplicação na mesma tela.
- Teste de carga com k6 2.4.0, executado como Job dentro do cluster.
- Scripts para subir, gerar carga, abrir o Grafana e derrubar o ambiente.
