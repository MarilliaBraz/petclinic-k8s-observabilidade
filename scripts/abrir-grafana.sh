#!/usr/bin/env bash
# Atividade 4 - Plataforma de Monitoramento e Observabilidade
# Grupo: Marillia Braz, Lucas Mendes e Pedro Henrique Feitosa
#
# Abre o Grafana em http://localhost:3000 (Ctrl+C encerra).
set -euo pipefail
echo "Grafana em http://localhost:3000 (usuario e senha em ambientes/local.env)"
kubectl -n observabilidade port-forward svc/grafana 3000:80
