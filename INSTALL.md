# Instalação

Como instalar as ferramentas, iniciar o cluster Minikube e criar a estrutura básica (namespaces, Secrets e imagem da aplicação). O funcionamento da aplicação e da observabilidade está no [README.md](README.md).

## Pré-requisitos

| Item | Mínimo |
|---|---|
| Sistema | Linux (testado no Ubuntu) com Docker instalado e o usuário no grupo `docker` |
| CPU e memória livres | 4 CPUs e 8 GB de RAM para o Minikube |
| Disco | Cerca de 10 GB para as imagens |
| Rede | Acesso à internet para baixar imagens e charts |

Versões usadas (também em [scripts/versoes.env](scripts/versoes.env)):

| Ferramenta | Versão |
|---|---|
| Minikube | v1.39.0 |
| Kubernetes | v1.37.0 |
| kubectl | v1.37.2 |
| Helm | v4.3.2 |

## 1. Instalar kubectl, Minikube e Helm

Os binários ficam em `~/.local/bin`, sem precisar de `sudo`:

```bash
mkdir -p ~/.local/bin
curl -Lo ~/.local/bin/kubectl "https://dl.k8s.io/release/v1.37.2/bin/linux/amd64/kubectl"
curl -Lo ~/.local/bin/minikube https://github.com/kubernetes/minikube/releases/download/v1.39.0/minikube-linux-amd64
curl -L https://get.helm.sh/helm-v4.3.2-linux-amd64.tar.gz | tar xz -C /tmp
mv /tmp/linux-amd64/helm ~/.local/bin/
chmod +x ~/.local/bin/kubectl ~/.local/bin/minikube
```

Se `~/.local/bin` não estiver no `PATH`, adicione ao `~/.bashrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Conferir:

```bash
docker version --format '{{.Server.Version}}'
minikube version
kubectl version --client
helm version --short
```

## 2. Iniciar o cluster

```bash
minikube start --driver=docker --kubernetes-version=v1.37.0 \
  --cpus=4 --memory=8192 --disk-size=30g
kubectl config use-context minikube
```

Conferir que o cluster está pronto:

```bash
minikube status
kubectl get nodes
```

Saída esperada:

```
NAME       STATUS   ROLES           AGE   VERSION
minikube   Ready    control-plane   1m    v1.37.0
```

## 3. Construir a imagem da aplicação

A imagem é construída a partir do código oficial do Spring PetClinic, em um commit fixo, e carregada dentro do Minikube:

```bash
docker build -t petclinic:4.0.0-500158f app/
minikube image load petclinic:4.0.0-500158f
minikube image ls | grep petclinic
```

## 4. Criar a estrutura básica

### Namespaces

```bash
kubectl apply -f k8s/namespaces.yaml
kubectl get namespaces petclinic observabilidade
```

| Namespace | Conteúdo |
|---|---|
| `petclinic` | aplicação, banco e postgres-exporter |
| `observabilidade` | Prometheus, Grafana, Loki, Tempo e OpenTelemetry Collector |

### Credenciais

As senhas não ficam nos arquivos YAML. Elas vêm de `ambientes/local.env`, que não vai para o Git:

```bash
cp ambientes/local.env.example ambientes/local.env   # e troque as senhas
source ambientes/local.env

kubectl -n petclinic create secret generic banco-credenciais \
  --from-literal=BANCO_ADMIN_USUARIO="$BANCO_ADMIN_USUARIO" \
  --from-literal=BANCO_ADMIN_SENHA="$BANCO_ADMIN_SENHA" \
  --from-literal=BANCO_APP_SENHA="$BANCO_APP_SENHA" \
  --from-literal=BANCO_MONITORAMENTO_SENHA="$BANCO_MONITORAMENTO_SENHA"

kubectl -n observabilidade create secret generic grafana-admin \
  --from-literal=admin-user="$GRAFANA_USUARIO" \
  --from-literal=admin-password="$GRAFANA_SENHA"
```

As contas do banco são criadas uma única vez, na primeira subida do volume. Para trocar uma senha depois disso, apague o ambiente (`scripts/derrubar.sh --apagar`) e suba de novo, ou altere a conta no PostgreSQL com `ALTER ROLE` antes de atualizar o Secret.

Com isso o cluster está pronto para receber o banco, a aplicação e a stack de observabilidade. Os próximos passos estão no [README.md](README.md#etapa-2-banco-de-dados).

## Atalho: tudo com um comando

O script `scripts/subir.sh` faz os passos 2 a 4 deste arquivo e as etapas seguintes do README (banco, aplicação e observabilidade), na ordem. Se `ambientes/local.env` não existir, ele cria um com senhas aleatórias. Pode ser executado de novo sem problema, porque cada passo só aplica diferenças.

```bash
scripts/subir.sh
```

## Problemas comuns

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `minikube start` falha com erro de permissão no Docker | usuário fora do grupo `docker` | `sudo usermod -aG docker $USER` e abrir uma nova sessão |
| `minikube start` reclama de memória | menos de 8 GB livres | fechar programas ou reduzir `--memory` (abaixo de 6144 a stack pode não subir) |
| Pod da aplicação em `ErrImageNeverPull` ou `ImagePullBackOff` | imagem não carregada no Minikube | repetir o passo 3 |
| `kubectl` aponta para outro cluster | contexto errado | `kubectl config use-context minikube` |

## Encerrar

```bash
scripts/derrubar.sh            # para o cluster e mantém os dados
scripts/derrubar.sh --apagar   # apaga o cluster e todos os dados
```
