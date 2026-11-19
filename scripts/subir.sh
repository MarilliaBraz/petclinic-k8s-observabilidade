#!/usr/bin/env bash
# Atividade 4 - Plataforma de Monitoramento e Observabilidade
# Grupo: Marillia Braz, Lucas Mendes e Pedro Henrique Feitosa
#
# Sobe o ambiente completo, na ordem das etapas do enunciado:
#   1. cluster Minikube
#   2. banco de dados
#   3. aplicacao replicada
#   4. stack de observabilidade
# Pode ser executado de novo sem problema: cada passo so aplica diferencas.
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
source "$RAIZ/scripts/versoes.env"
ARQUIVO_AMBIENTE="$RAIZ/ambientes/local.env"
K8S="$RAIZ/k8s"
OBS="$K8S/observabilidade"

etapa() { printf '\n==> %s\n' "$*"; }

gerar_senha() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24; }

preparar_ambiente() {
  if [[ ! -f "$ARQUIVO_AMBIENTE" ]]; then
    etapa "Criando ambientes/local.env com senhas aleatorias"
    umask 077
    sed -e "s/troque-esta-senha/__SENHA__/" "$RAIZ/ambientes/local.env.example" \
      | while IFS= read -r linha; do echo "${linha/__SENHA__/$(gerar_senha)}"; done \
      > "$ARQUIVO_AMBIENTE"
  fi
  # shellcheck disable=SC1090
  source "$ARQUIVO_AMBIENTE"
}

subir_cluster() {
  etapa "Etapa 1: cluster Minikube ($KUBERNETES_VERSION)"
  if ! minikube status >/dev/null 2>&1; then
    minikube start --driver=docker --kubernetes-version="$KUBERNETES_VERSION" \
      --cpus="$MINIKUBE_CPUS" --memory="$MINIKUBE_MEMORIA_MB" --disk-size="$MINIKUBE_DISCO"
  fi
  # Garante que nada sera aplicado em outro cluster configurado no kubectl
  kubectl config use-context minikube >/dev/null
  kubectl wait --for=condition=Ready node --all --timeout=180s
  kubectl get nodes
}

conferir_versao_da_imagem() {
  # O Deployment precisa usar a mesma imagem que este script constroi
  if ! grep -q "image: $PETCLINIC_IMAGEM\$" "$K8S/app-deployment.yaml"; then
    echo "ERRO: k8s/app-deployment.yaml nao usa $PETCLINIC_IMAGEM (scripts/versoes.env)" >&2
    exit 1
  fi
}

construir_imagem() {
  etapa "Imagem da aplicacao: $PETCLINIC_IMAGEM"
  conferir_versao_da_imagem
  local imagens
  imagens="$(minikube image ls)"
  if [[ "$imagens" == *"$PETCLINIC_IMAGEM"* ]]; then
    echo "imagem ja carregada no Minikube"
    return
  fi
  docker build --build-arg PETCLINIC_COMMIT="$PETCLINIC_COMMIT" -t "$PETCLINIC_IMAGEM" "$RAIZ/app"
  minikube image load "$PETCLINIC_IMAGEM"
}

criar_segredos() {
  etapa "Namespaces e Secrets (valores de ambientes/local.env)"
  kubectl apply -f "$K8S/namespaces.yaml"
  kubectl -n petclinic create secret generic banco-credenciais \
    --from-literal=BANCO_ADMIN_USUARIO="$BANCO_ADMIN_USUARIO" \
    --from-literal=BANCO_ADMIN_SENHA="$BANCO_ADMIN_SENHA" \
    --from-literal=BANCO_APP_SENHA="$BANCO_APP_SENHA" \
    --from-literal=BANCO_MONITORAMENTO_SENHA="$BANCO_MONITORAMENTO_SENHA" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n observabilidade create secret generic grafana-admin \
    --from-literal=admin-user="$GRAFANA_USUARIO" \
    --from-literal=admin-password="$GRAFANA_SENHA" \
    --dry-run=client -o yaml | kubectl apply -f -
}

instalar_chart() { # <release> <chart> <versao> <namespace> <values>
  helm upgrade --install "$1" "$2" --version "$3" --namespace "$4" \
    --values "$5" --wait --timeout 10m
}

instalar_observabilidade() {
  etapa "Etapa 4: stack de observabilidade"
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
  helm repo add grafana-community https://grafana-community.github.io/helm-charts >/dev/null
  helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null
  helm repo update >/dev/null
  instalar_chart kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    "$CHART_KUBE_PROMETHEUS_STACK" observabilidade "$OBS/kube-prometheus-stack.values.yaml"
  instalar_chart loki grafana-community/loki "$CHART_LOKI" observabilidade "$OBS/loki.values.yaml"
  instalar_chart tempo grafana-community/tempo "$CHART_TEMPO" observabilidade "$OBS/tempo.values.yaml"
  instalar_chart otel-collector open-telemetry/opentelemetry-collector \
    "$CHART_OTEL_COLLECTOR" observabilidade "$OBS/otel-collector.values.yaml"
  kubectl apply -f "$OBS/painel-petclinic.yaml"
}

implantar_banco() {
  etapa "Etapa 2: banco de dados"
  kubectl apply -f "$K8S/banco-configmap.yaml"
  kubectl apply -f "$K8S/banco-deployment.yaml"
  kubectl apply -f "$K8S/banco-service.yaml"
  kubectl -n petclinic rollout status statefulset/banco --timeout=180s
  instalar_chart banco-exporter prometheus-community/prometheus-postgres-exporter \
    "$CHART_POSTGRES_EXPORTER" petclinic "$OBS/postgres-exporter.values.yaml"
}

implantar_aplicacao() {
  etapa "Etapa 3: aplicacao replicada"
  kubectl apply -f "$K8S/app-configmap.yaml"
  kubectl apply -f "$K8S/app-deployment.yaml"
  kubectl apply -f "$K8S/app-service.yaml"
  # Mudou so o app-config? Os pods leem o ConfigMap ao iniciar, entao rode
  # depois: kubectl -n petclinic rollout restart deployment/petclinic
  kubectl -n petclinic rollout status deployment/petclinic --timeout=300s
}

resumo() {
  etapa "Pronto"
  kubectl config set-context --current --namespace=petclinic >/dev/null
  kubectl get pods -n petclinic -o wide
  echo
  echo "Aplicacao: $(minikube service app-service -n petclinic --url)"
  echo "Grafana:   scripts/abrir-grafana.sh  (usuario e senha em ambientes/local.env)"
  echo "Carga:     scripts/gerar-carga.sh"
}

preparar_ambiente
subir_cluster
construir_imagem
criar_segredos
# A observabilidade sobe antes da aplicacao para que nenhuma telemetria
# do primeiro start (logs de inicializacao, primeiros traces) se perca.
instalar_observabilidade
implantar_banco
implantar_aplicacao
resumo
