#!/usr/bin/env python3
# Atividade 4 - Plataforma de Monitoramento e Observabilidade
# Grupo: Marillia Braz, Lucas Mendes e Pedro Henrique Feitosa
#
# Gera k8s/observabilidade/painel-petclinic.yaml (ConfigMap com o painel do
# Grafana). O painel e escrito aqui em Python para nao manter um JSON de
# centenas de linhas na mao. Uso: python3 scripts/painel/gerar-painel.py
import json
import pathlib

PROM = {"type": "prometheus", "uid": "prometheus"}
LOKI = {"type": "loki", "uid": "loki"}
TEMPO = {"type": "tempo", "uid": "tempo"}

# Exclui as probes do Kubernetes (/actuator/health) das metricas de requisicao
APP = 'service_name="petclinic",http_route!~"/actuator.*"'
NS = 'namespace="petclinic"'


def posicao(x, y, w, h):
    return {"x": x, "y": y, "w": w, "h": h}


def estatistica(titulo, expr, x, y, unidade="none", descricao=""):
    return {
        "type": "stat", "title": titulo, "description": descricao,
        "datasource": PROM, "gridPos": posicao(x, y, 4, 4),
        "fieldConfig": {"defaults": {"unit": unidade, "decimals": 2 if unidade != "none" else 0}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "value"},
        "targets": [{"refId": "A", "expr": expr}],
    }


def serie(titulo, alvos, x, y, w=8, unidade="short", descricao=""):
    return {
        "type": "timeseries", "title": titulo, "description": descricao,
        "datasource": PROM, "gridPos": posicao(x, y, w, 8),
        "fieldConfig": {"defaults": {"unit": unidade, "custom": {"fillOpacity": 10}}},
        "options": {"legend": {"displayMode": "list", "placement": "bottom"}},
        "targets": [{"refId": chr(65 + i), "expr": e, "legendFormat": l} for i, (e, l) in enumerate(alvos)],
    }


def logs(titulo, expr, x, y, w, altura=10):
    return {
        "type": "logs", "title": titulo, "datasource": LOKI, "gridPos": posicao(x, y, w, altura),
        "options": {"showTime": True, "wrapLogMessage": True, "sortOrder": "Descending",
                    "enableLogDetails": True},
        "targets": [{"refId": "A", "expr": expr, "queryType": "range"}],
    }


def linha(titulo, y):
    return {"type": "row", "title": titulo, "collapsed": False, "gridPos": posicao(0, y, 24, 1)}


paineis = [
    linha("Métricas (Prometheus)", 0),
    estatistica("Réplicas da aplicação prontas",
                f'sum(kube_deployment_status_replicas_available{{{NS},deployment="petclinic"}})', 0, 1),
    estatistica("Banco de dados pronto",
                f'sum(kube_statefulset_status_replicas_ready{{{NS},statefulset="banco"}})', 4, 1),
    estatistica("Requisições por segundo",
                f'sum(rate(http_server_request_duration_seconds_count{{{APP}}}[1m]))', 8, 1, "reqps"),
    estatistica("Erros (5xx)",
                f'sum(rate(http_server_request_duration_seconds_count{{{APP},http_response_status_code=~"5.."}}[5m]))'
                f' / sum(rate(http_server_request_duration_seconds_count{{{APP}}}[5m]))', 12, 1, "percentunit"),
    estatistica("Latência p95",
                f'histogram_quantile(0.95, sum by (le) (rate(http_server_request_duration_seconds_bucket{{{APP}}}[5m])))',
                16, 1, "s"),
    estatistica("Conexões no banco",
                'sum(pg_stat_activity_count{datname="petclinic"})', 20, 1),
    serie("Requisições por réplica (balanceamento de carga)",
          [(f'sum by (k8s_pod_name) (rate(http_server_request_duration_seconds_count{{{APP}}}[1m]))',
            "{{k8s_pod_name}}")], 0, 5, unidade="reqps",
          descricao="Cada linha é uma réplica. Linhas próximas mostram o Service dividindo a carga."),
    serie("CPU por pod",
          [(f'sum by (pod) (rate(container_cpu_usage_seconds_total{{{NS},container!=""}}[2m]))', "{{pod}}")],
          8, 5, unidade="cores"),
    serie("Memória por pod",
          [(f'sum by (pod) (container_memory_working_set_bytes{{{NS},container!=""}})', "{{pod}}")],
          16, 5, unidade="bytes"),
    linha("Logs (Loki)", 13),
    logs("Logs da aplicação (clique no trace_id para abrir o trace)",
         # Esconde as probes do Kubernetes e o "Completed 200 OK" de cada uma
         '{k8s_namespace_name="petclinic", k8s_container_name="petclinic"}'
         ' != "/actuator/health" != "Completed 200 OK"', 0, 14, 14),
    logs("Logs do banco de dados (INSERT, UPDATE, DELETE)",
         '{k8s_namespace_name="petclinic", k8s_container_name="postgres"}'
         ' |~ "(?i)insert into|update |delete from|error|fatal"', 14, 14, 10),
    # Mesmos logs da aplicacao, coletados pelo Promtail (stack PLG). Os
    # rotulos sao os do Promtail (namespace, container), nao os do Collector.
    logs("Logs da aplicação coletados pelo Promtail (PLG)",
         '{coletor="promtail", namespace="petclinic", container="petclinic"}'
         ' != "/actuator/health" != "Completed 200 OK"', 0, 24, 24, altura=8),
    linha("Traces (Tempo)", 32),
    {
        "type": "table", "title": "Últimas requisições rastreadas (clique no trace)",
        "datasource": TEMPO, "gridPos": posicao(0, 33, 14, 10),
        # A coluna "nested" (spans internos) so polui a tabela
        "transformations": [{"id": "organize", "options": {"excludeByName": {"nested": True}}}],
        "targets": [{"refId": "A", "queryType": "traceql", "limit": 20,
                     "query": '{resource.service.name="petclinic" && span.http.route != "" && span.http.route !~ "/actuator.*"}'}],
    },
    {
        "type": "nodeGraph", "title": "Mapa de serviços (gerado a partir dos traces)",
        "datasource": TEMPO, "gridPos": posicao(14, 33, 10, 10),
        "targets": [{"refId": "A", "queryType": "serviceMap"}],
    },
]

for numero, painel in enumerate(paineis, start=1):
    painel["id"] = numero

painel_grafana = {
    "uid": "petclinic-observabilidade",
    "title": "PetClinic: métricas, logs e traces",
    "tags": ["petclinic", "atividade-4"],
    "timezone": "browser",
    "schemaVersion": 39,
    "refresh": "10s",
    "time": {"from": "now-15m", "to": "now"},
    "panels": paineis,
}

cabecalho = """# Atividade 4 - Plataforma de Monitoramento e Observabilidade
# Grupo: Marillia Braz, Lucas Mendes e Pedro Henrique Feitosa
#
# Painel do Grafana com metricas (Prometheus), logs (Loki) e traces (Tempo)
# da aplicacao. O Grafana carrega sozinho todo ConfigMap com o rotulo
# grafana_dashboard. Arquivo gerado por scripts/painel/gerar-painel.py:
# altere o script, nao este arquivo.
"""
conteudo = json.dumps(painel_grafana, ensure_ascii=False, indent=2)
yaml = (cabecalho
        + "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: painel-petclinic\n"
        + "  namespace: observabilidade\n  labels:\n    grafana_dashboard: \"1\"\n"
        + "data:\n  petclinic.json: |\n"
        + "\n".join("    " + l for l in conteudo.splitlines()) + "\n")
destino = pathlib.Path(__file__).resolve().parents[2] / "k8s/observabilidade/painel-petclinic.yaml"
destino.write_text(yaml, encoding="utf-8")
print(f"gerado: {destino}")
