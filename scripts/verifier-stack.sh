#!/usr/bin/env bash
# Vérifie que la stack démarrée répond et fonctionne vraiment :
# chaque service est prêt, Prometheus collecte des mesures,
# les alertes sont chargées et le tableau de bord Grafana existe.
set -euo pipefail

GRAFANA_MOT_DE_PASSE="${GRAFANA_MOT_DE_PASSE:-changez-moi}"

attendre() {
  local nom="$1" url="$2"
  for _ in $(seq 1 30); do
    if curl -fsS -o /dev/null "$url"; then
      echo "OK   $nom"
      return 0
    fi
    sleep 3
  done
  echo "ÉCHEC $nom ne répond pas ($url)"
  return 1
}

attendre "Prometheus"   http://localhost:9090/-/ready
attendre "Alertmanager" http://localhost:9093/-/ready
attendre "Blackbox"     http://localhost:9115/-/healthy
attendre "Grafana"      http://localhost:3000/api/health

# Prometheus doit avoir collecté le serveur de démonstration.
for _ in $(seq 1 30); do
  etat=$(curl -fsS 'http://localhost:9090/api/v1/query?query=up%7Bjob%3D%22linux%22%7D' | jq -r '.data.result[0].value[1] // "absent"')
  [ "$etat" = "1" ] && break
  sleep 3
done
if [ "$etat" != "1" ]; then
  echo "ÉCHEC Prometheus ne collecte pas le serveur de démonstration (état : $etat)"
  exit 1
fi
echo "OK   Prometheus collecte le serveur de démonstration"

# Les règles d'alerte doivent être chargées.
nb_regles=$(curl -fsS http://localhost:9090/api/v1/rules | jq '[.data.groups[].rules[]] | length')
if [ "$nb_regles" -lt 1 ]; then
  echo "ÉCHEC aucune règle d'alerte chargée"
  exit 1
fi
echo "OK   $nb_regles règles d'alerte chargées"

# Le tableau de bord doit avoir été créé automatiquement dans Grafana.
curl -fsS -o /dev/null -u "admin:$GRAFANA_MOT_DE_PASSE" \
  http://localhost:3000/api/dashboards/uid/vue-multi-clients
echo "OK   tableau de bord « Vue multi-clients » présent dans Grafana"
