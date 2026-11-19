#!/usr/bin/env bash
# Atividade 4 - Plataforma de Monitoramento e Observabilidade
# Grupo: Marillia Braz, Lucas Mendes e Pedro Henrique Feitosa
#
# Roda o teste de carga do k6 dentro do cluster (Job) e mostra o resultado.
# Uso: scripts/gerar-carga.sh [usuarios virtuais] [duracao]
#      scripts/gerar-carga.sh 5 2m
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
USUARIOS="${1:-5}"
DURACAO="${2:-2m}"
[[ "$USUARIOS" =~ ^[0-9]+$ ]] || { echo "usuarios deve ser um numero" >&2; exit 2; }
[[ "$DURACAO" =~ ^[0-9]+[smh]$ ]] || { echo "duracao no formato 30s, 2m ou 1h" >&2; exit 2; }

kubectl config use-context minikube >/dev/null

kubectl -n petclinic delete job carga-k6 --ignore-not-found --wait=true >/dev/null
sed -e "s/__USUARIOS__/$USUARIOS/" -e "s/__DURACAO__/$DURACAO/" "$RAIZ/k8s/carga-job.yaml" \
  | kubectl apply -f -
# O pod do Job leva alguns instantes para existir depois do apply
until kubectl -n petclinic get pod -l job-name=carga-k6 -o name | grep -q pod; do sleep 1; done
kubectl -n petclinic wait --for=condition=Ready pod -l job-name=carga-k6 --timeout=120s
kubectl -n petclinic logs -f job/carga-k6
