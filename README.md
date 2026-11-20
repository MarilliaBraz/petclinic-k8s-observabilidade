# PetClinic no Kubernetes com observabilidade

Atividade 4, Plataforma de Monitoramento e Observabilidade.

Instalação do ambiente: [INSTALL.md](INSTALL.md).

| Integrante | GitHub |
|---|---|
| Marillia Braz | [@MarilliaBraz](https://github.com/MarilliaBraz) |
| Lucas Mendes | [@LucasMNDL3](https://github.com/LucasMNDL3) |
| Pedro Henrique Feitosa | [@feitosapedrofatesg-svg](https://github.com/feitosapedrofatesg-svg) |

## A aplicação

O [Spring PetClinic](https://github.com/spring-projects/spring-petclinic) é a aplicação de referência do Spring Boot: um sistema de clínica veterinária com cadastro de donos, pets, visitas e veterinários. Usa Java, Spring Boot, Spring Data JPA e Thymeleaf, com PostgreSQL como banco.

Escolhemos o PetClinic porque Java com Spring Boot e PostgreSQL é a combinação mais comum nos sistemas corporativos do mercado brasileiro (bancos, seguradoras, varejo). Assim, o que está montado aqui é o que uma equipe de plataforma faria com um sistema real: subir no Kubernetes e enxergar o que acontece dentro dele.

## Arquitetura

```
                         Navegador
                             |
                   app-service (NodePort 30080)
                     /                  \
          petclinic (réplica 1)   petclinic (réplica 2)      namespace petclinic
                     \                  /
                   banco-service (ClusterIP 5432)
                             |
                     banco-0 (PostgreSQL)  <--  postgres-exporter
 ----------------------------------------------------------------------------
                                                              namespace observabilidade
   agente OTel (traces, métricas) --OTLP-->  OpenTelemetry Collector  <-- logs dos pods
                                              |        |         |
                                            Tempo   Prometheus   Loki  <--  Promtail <-- logs dos pods
                                              \        |         /         (namespace petclinic)
                                                    Grafana
```

| Sinal | Origem | Caminho | Destino |
|---|---|---|---|
| Métricas do cluster | kube-state-metrics, node-exporter, kubelet | coleta do Prometheus | Prometheus |
| Métricas da aplicação | agente Java do OpenTelemetry | OTLP para o Collector | Prometheus (receptor OTLP) |
| Métricas do banco | postgres-exporter | coleta do Prometheus | Prometheus |
| Logs | stdout de todos os pods | Collector lê os arquivos do nó | Loki (endpoint OTLP) |
| Logs (PLG) | stdout dos pods do namespace `petclinic` | Promtail lê os arquivos do nó | Loki (API de push), com o rótulo `coletor="promtail"` |
| Traces | agente Java do OpenTelemetry | OTLP para o Collector | Tempo |

### Por que essas ferramentas

- **kube-prometheus-stack** é a forma padrão de monitorar Kubernetes: instala o Prometheus Operator, o Grafana e os painéis prontos de pods, nós e namespaces.
- **OpenTelemetry Collector** é o ponto único de entrada da telemetria. A aplicação só conhece o protocolo OTLP, que também é aceito por Datadog, New Relic, Dynatrace e Elastic. Trocar de ferramenta muda só os exporters do Collector.
- **Agente Java do OpenTelemetry** instrumenta a aplicação sem mudar o código. Cada requisição vira um trace com o span HTTP e os spans das consultas SQL.
- **Loki e Tempo** guardam logs e traces indexando só rótulos (namespace, pod, serviço), o que deixa o custo bem abaixo de soluções que indexam o texto inteiro.
- Os logs são lidos do stdout dos pods, como recomenda o [12-factor](https://12factor.net/pt_br/logs).
- **Promtail e Collector em paralelo.** O enunciado pede a stack PLG (Promtail, Loki, Grafana), então o Promtail está instalado e envia ao Loki os logs do namespace `petclinic`. O Collector continua enviando todos os logs por OTLP, que é o caminho recomendado hoje: a Grafana encerrou o suporte do Promtail em 2026 em favor do Collector e do Alloy. No Loki, as duas cópias se separam pelos rótulos: `{coletor="promtail", namespace="petclinic"}` traz as linhas do Promtail e `{k8s_namespace_name="petclinic"}` traz as do Collector.
- Os charts de Loki e Tempo vêm do repositório `grafana-community`, porque o chart `grafana/tempo` foi marcado como deprecado. O do Promtail só existe no repositório `grafana`, também marcado como deprecado.

## Estrutura do repositório

```
INSTALL.md                          instalação do Minikube e preparação do cluster
app/Dockerfile                      imagem do PetClinic (build do código oficial)
k8s/
  namespaces.yaml                   namespaces petclinic e observabilidade
  banco-configmap.yaml              parâmetros e script que cria as contas do banco
  banco-deployment.yaml             PostgreSQL (StatefulSet com volume)
  banco-service.yaml                Service ClusterIP do banco
  app-configmap.yaml                configuração da aplicação e do OpenTelemetry
  app-deployment.yaml               PetClinic com replicas: 2
  app-service.yaml                  Service NodePort da aplicação
  carga-job.yaml                    teste de carga com k6
  observabilidade/                  values do Helm e painel do Grafana
ambientes/local.env.example         modelo das credenciais (o local.env fica fora do Git)
scripts/
  versoes.env                       todas as versões usadas
  subir.sh                          sobe tudo, na ordem das etapas
  gerar-carga.sh                    roda o k6 dentro do cluster
  abrir-grafana.sh                  abre o Grafana em localhost:3000
  derrubar.sh                       para ou apaga o cluster
  painel/gerar-painel.py            gera o painel do Grafana
docs/evidencias/                    capturas de tela da entrega
```

## Instalação

A instalação do kubectl, do Minikube e do Helm, a subida do cluster, a imagem da aplicação, os namespaces e as credenciais estão no **[INSTALL.md](INSTALL.md)**. Em resumo: Linux com Docker, 4 CPUs, 8 GB de RAM e cerca de 10 GB de disco.

## Passo a passo

O script `scripts/subir.sh` executa todas as etapas de uma vez. Abaixo estão os mesmos comandos, etapa por etapa, como pede o enunciado. A etapa 1 (instalação e preparação do ambiente) está no [INSTALL.md](INSTALL.md).

### Etapa 2: banco de dados

```bash
kubectl apply -f k8s/banco-configmap.yaml
kubectl apply -f k8s/banco-deployment.yaml
kubectl apply -f k8s/banco-service.yaml
kubectl -n petclinic rollout status statefulset/banco
```

O banco roda como StatefulSet, que o enunciado permite. Na primeira subida, o script `01-criar-usuarios.sh` (no ConfigMap) cria três contas:

| Conta | Para quê | Permissões |
|---|---|---|
| `postgres` | administração | superusuário, usado só na criação |
| `petclinic` | aplicação | dona do banco `petclinic`, sem superusuário |
| `monitoramento` | postgres-exporter | papel `pg_monitor`, só lê estatísticas |

### Etapa 3: aplicação replicada

```bash
kubectl apply -f k8s/app-configmap.yaml
kubectl apply -f k8s/app-deployment.yaml
kubectl apply -f k8s/app-service.yaml

# petclinic como namespace padrao: assim "kubectl get pods" ja mostra a aplicacao e o banco
kubectl config set-context --current --namespace=petclinic
kubectl get pods
```

A ligação com o banco é feita por variáveis de ambiente no Deployment: `DB_HOST=banco-service`, `DB_PORT=5432` e `DB_NAME=petclinic` vêm do `app-config`, e a senha vem do Secret `banco-credenciais`.

### Etapa 4: stack de observabilidade

```bash
source scripts/versoes.env
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version "$CHART_KUBE_PROMETHEUS_STACK" -n observabilidade \
  -f k8s/observabilidade/kube-prometheus-stack.values.yaml --wait --timeout 10m
helm upgrade --install loki grafana-community/loki --version "$CHART_LOKI" \
  -n observabilidade -f k8s/observabilidade/loki.values.yaml --wait --timeout 10m
helm upgrade --install promtail grafana/promtail --version "$CHART_PROMTAIL" \
  -n observabilidade -f k8s/observabilidade/promtail.values.yaml --wait --timeout 10m
helm upgrade --install tempo grafana-community/tempo --version "$CHART_TEMPO" \
  -n observabilidade -f k8s/observabilidade/tempo.values.yaml --wait --timeout 10m
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  --version "$CHART_OTEL_COLLECTOR" -n observabilidade \
  -f k8s/observabilidade/otel-collector.values.yaml --wait --timeout 10m
helm upgrade --install banco-exporter prometheus-community/prometheus-postgres-exporter \
  --version "$CHART_POSTGRES_EXPORTER" -n petclinic \
  -f k8s/observabilidade/postgres-exporter.values.yaml --wait --timeout 10m
kubectl apply -f k8s/observabilidade/painel-petclinic.yaml
```

### Etapa 5: validação e testes

```bash
minikube service app-service -n petclinic --url   # endereço da aplicação
scripts/gerar-carga.sh 5 2m                       # 5 usuários virtuais por 2 minutos
scripts/abrir-grafana.sh                          # Grafana em http://localhost:3000
```

No Grafana, abra o painel **PetClinic: métricas, logs e traces**. Ele mostra:

- **Métricas (Prometheus):** réplicas prontas, banco pronto, requisições por segundo, erros, latência p95, conexões no banco, CPU e memória por pod.
- **Balanceamento de carga:** o gráfico "Requisições por réplica" tem uma linha por pod. Linhas próximas mostram o Service dividindo as requisições (ver o item 2 de "Problemas encontrados").
- **Logs (Loki):** logs da aplicação, com o `trace_id` de cada requisição, e logs do banco com cada `INSERT` feito pelos cadastros. Logo abaixo, os mesmos logs da aplicação coletados pelo Promtail.
- **Traces (Tempo):** as últimas requisições rastreadas e o mapa de serviços (petclinic para postgresql), montado a partir dos traces.

Para investigar uma requisição: abra um trace na tabela, veja o span da consulta SQL e use **Logs for this span** para ir aos logs daquela requisição. No sentido contrário, o `trace_id` de uma linha de log abre o trace correspondente.

## Evidências

### `kubectl get pods`: 2 réplicas da aplicação e o banco rodando

Saída do terminal com o cluster Minikube pronto, os pods da aplicação (`petclinic-*`, 2 réplicas) e do banco (`banco-0`), os Services e a URL da aplicação.

![kubectl get pods](docs/evidencias/01-kubectl-get-pods.png)

### Aplicação funcionando no navegador

Cadastro de um dono pelo formulário do PetClinic, acessado pelo `app-service`:

![Formulário de cadastro](docs/evidencias/02-aplicacao.png)

Depois de salvar, a aplicação lê o registro de volta do banco (id 292):

![Dono cadastrado](docs/evidencias/03-cadastro-no-banco.png)

### Grafana: métricas do Prometheus, logs do Loki e traces do Tempo

O painel **PetClinic: métricas, logs e traces** durante o teste de carga, com as três fontes na mesma tela. Em cima, as métricas: réplicas prontas, banco pronto, requisições por segundo, erros, latência, conexões no banco, requisições por réplica, CPU e memória por pod. No meio, os logs da aplicação (com `trace_id`) e do banco (com cada `insert into owners`). Embaixo, os traces e o mapa de serviços `user`, `petclinic` e `banco-service`.

![Painel do Grafana](docs/evidencias/04-grafana-painel-completo.png)

Trace de um cadastro aberto no Tempo: a requisição `POST /owners/new` passa pelo `OwnerRepository.save` e termina no `INSERT petclinic.owners` do PostgreSQL. O botão **Related logs** leva aos logs dessa requisição no Loki.

![Trace de um cadastro](docs/evidencias/06-grafana-trace-cadastro.png)

Mais capturas, em tamanho maior: [métricas](docs/evidencias/04-grafana-metricas.png) e [logs e traces](docs/evidencias/05-grafana-logs-traces.png).

O mesmo cadastro conferido direto no banco:

```
$ kubectl -n petclinic exec banco-0 -- psql -U postgres -d petclinic \
    -c "SELECT id, first_name, last_name, city, telephone FROM owners WHERE last_name = 'Observabilidade';"
 id  | first_name |    last_name    |  city   | telephone
-----+------------+-----------------+---------+------------
 292 | Ana        | Observabilidade | Goiania | 6232104455
```

Resultado do teste de carga (6 usuários virtuais por 4 minutos):

```
checks_succeeded...: 100.00% 3091 out of 3091
http_req_failed....: 0.00%   0 out of 3313
http_reqs..........: 3313    13.73/s
```

## Decisões técnicas

O projeto segue três pilares de manutenção:

- **Parametrização:** endereço do banco, configuração do OpenTelemetry, nível e formato de log ficam em ConfigMaps. Mudar um valor não exige gerar outra imagem.
- **Ambiente:** credenciais ficam em Secrets criados a partir de `ambientes/local.env`, que não vai para o Git. O repositório tem só o modelo `local.env.example`.
- **Versão:** nenhuma imagem ou chart usa `latest`. Todas as versões ficam em `scripts/versoes.env` e nos manifestos, e as mudanças são registradas no [CHANGELOG.md](CHANGELOG.md).

Outras escolhas:

- **Imagem própria do PetClinic.** A imagem publicada pelo projeto roda como binário nativo (GraalVM), e o agente do OpenTelemetry precisa de JVM. Por isso o `app/Dockerfile` compila o código oficial em um commit fixo.
- **Agente injetado por initContainer.** O agente é copiado para o pod na inicialização, a mesma técnica do OpenTelemetry Operator. A imagem da aplicação não depende da ferramenta de observabilidade.
- **Actuator restrito.** O PetClinic expõe todos os endpoints do Actuator por padrão, inclusive `/env` e `/heapdump`. Aqui ficam abertos só `health` e `info`, usados pelas probes.
- **Probes e limites.** Todos os pods têm `requests` e `limits` de recursos. A aplicação tem `startupProbe`, `readinessProbe` e `livenessProbe`, então só recebe tráfego quando está pronta.
- **Atualização sem queda.** O Deployment usa `maxUnavailable: 0`: numa atualização, um pod novo fica pronto antes de um antigo sair.

## Problemas encontrados

Quatro situações apareceram durante a validação. Todas são comuns em ambientes reais.

1. **O banco reiniciava sozinho.** A `livenessProbe` do PostgreSQL usava o tempo limite padrão do Kubernetes, 1 segundo. Enquanto as duas JVMs da aplicação subiam e disputavam a CPU, o `pg_isready` passou desse tempo e o kubelet reiniciou um banco saudável. Correção: `timeoutSeconds: 5` e `failureThreshold: 6` nas probes do banco.
2. **A carga não se dividia por igual entre as réplicas.** O Service do Kubernetes distribui **conexões**, não requisições. Com keep-alive, cada usuário virtual do k6 ficava preso a uma réplica (a divisão chegou a 7,3 contra 3,2 requisições por segundo). Com uma conexão por requisição (`noConnectionReuse`), a divisão ficou em 751 contra 755. Em produção, quem divide por requisição é um Ingress ou um service mesh.
3. **O log por requisição não aparecia.** A variável `LOGGING_LEVEL_..._DISPATCHERSERVLET` é convertida para minúsculas pelo Spring Boot, e o nome do logger `DispatcherServlet` diferencia maiúsculas. O nível passou a ser definido em `SPRING_APPLICATION_JSON`, que preserva o nome.
4. **Os traces das probes escondiam as requisições reais.** Cada pod recebe uma chamada de `/actuator/health` a cada poucos segundos. Um `filter` no Collector descarta esses spans antes de chegarem ao Tempo, e o painel ignora essas rotas.

## Encerrar

```bash
scripts/derrubar.sh            # para o cluster e mantém os dados
scripts/derrubar.sh --apagar   # apaga o cluster e todos os dados
```
