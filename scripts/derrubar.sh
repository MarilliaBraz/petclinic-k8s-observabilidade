#!/usr/bin/env bash
# Atividade 4 - Plataforma de Monitoramento e Observabilidade
# Grupo: Marillia Braz, Lucas Mendes e Pedro Henrique Feitosa
#
# Uso: scripts/derrubar.sh          para o cluster (dados preservados)
#      scripts/derrubar.sh --apagar apaga o cluster e todos os dados
set -euo pipefail
if [[ "${1:-}" == "--apagar" ]]; then
  minikube delete
else
  minikube stop
fi
