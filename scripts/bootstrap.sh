#!/usr/bin/env bash
set -euo pipefail

# Uso:
# ./scripts/bootstrap.sh owner/repo1 owner/repo2 ...
# Requiere: gh CLI autenticado (gh auth login)

# Configuración
OWNER="your-org-or-user"    # ⚙️ Cambia esto por tu org real
SYNC_MANAGER="sync-manager" # ⚙️ Nombre del repo central
TEMPLATE="./templates/call-sync-template.yml"

# Validación de argumentos
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 owner/repo1 [owner/repo2 ...]" >&2
  exit 1
fi

# Validación de dependencias
if ! command -v gh &> /dev/null; then
  echo "Error: GitHub CLI (gh) no está instalado o no está en el PATH." >&2
  exit 1
fi

# Validación de autenticación
if ! gh auth status &> /dev/null; then
  echo "Error: No estás autenticado en GitHub CLI. Ejecutá 'gh auth login' primero." >&2
  exit 1
fi

# Validación de template
if [ ! -f "$TEMPLATE" ]; then
  echo "Error: El archivo de template '$TEMPLATE' no existe." >&2
  exit 1
fi

# Solicitud de credenciales
read -p "Bitbucket username: " BB_USER
if [ -z "$BB_USER" ]; then
  echo "Error: El username de Bitbucket no puede estar vacío." >&2
  exit 1
fi

read -s -p "Bitbucket PAT: " BB_PAT
echo
if [ -z "$BB_PAT" ]; then
  echo "Error: El PAT de Bitbucket no puede estar vacío." >&2
  exit 1
fi

read -p "Bitbucket repo URL (sin https://, ej: git.gbsj.com.ar/scm/mob/repo.git): " BB_URL
echo
if [ -z "$BB_URL" ]; then
  echo "Error: La URL del repo de Bitbucket no puede estar vacía." >&2
  exit 1
fi

# Validación de formato de URL
if [[ "$BB_URL" =~ ^https?:// ]]; then
  echo "Error: La URL no debe incluir el protocolo (https://). Solo la ruta." >&2
  exit 1
fi

# Procesamiento de repositorios
for repo in "$@"; do
  echo "Configurando $repo..."

  # Validación de formato del repositorio
  if [[ ! "$repo" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$ ]]; then
    echo "⚠️  Advertencia: El formato del repo '$repo' parece incorrecto. Debe ser 'owner/repo'." >&2
    read -p "¿Continuar de todas formas? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Saltando $repo."
      continue
    fi
  fi

  # Verificación de existencia del repositorio
  if ! gh repo view "$repo" &> /dev/null; then
    echo "Error: El repositorio '$repo' no existe o no tenés acceso." >&2
    continue
  fi

  # Configuración de secrets
  if ! echo -n "$BB_USER" | gh secret set BITBUCKET_USER -R "$repo" 2>/dev/null; then
    echo "Error: No se pudo configurar el secret BITBUCKET_USER en $repo." >&2
    continue
  fi

  if ! echo -n "$BB_PAT" | gh secret set BITBUCKET_PAT -R "$repo" 2>/dev/null; then
    echo "Error: No se pudo configurar el secret BITBUCKET_PAT en $repo." >&2
    continue
  fi

  if ! echo -n "$BB_URL" | gh secret set BITBUCKET_REPO_URL -R "$repo" 2>/dev/null; then
    echo "Error: No se pudo configurar el secret BITBUCKET_REPO_URL en $repo." >&2
    continue
  fi

  # Preparación del workflow
  TMP=$(mktemp)
  trap 'rm -f "$TMP"' EXIT

  sed "s|OWNER|${OWNER}|g; s|sync-manager|${SYNC_MANAGER}|g" "$TEMPLATE" > "$TMP"

  # Obtener SHA del archivo existente si existe (para actualizaciones)
  EXISTING_SHA=$(gh api "repos/$repo/contents/.github/workflows/call-sync.yml" \
    --jq .sha 2>/dev/null || echo "")

  # Preparar argumentos para la API
  API_ARGS=(
    -f message="Add/Update call-sync workflow"
    -F content="$(base64 -w0 < "$TMP" 2>/dev/null || base64 < "$TMP")"
  )

  if [ -n "$EXISTING_SHA" ]; then
    API_ARGS+=(-f sha="$EXISTING_SHA")
  fi

  # Crear o actualizar el workflow
  DEFAULT_BRANCH=$(gh api "repos/$repo" --jq .default_branch)
  API_ARGS+=(-F branch="$DEFAULT_BRANCH")

  if gh api -X PUT "repos/$repo/contents/.github/workflows/call-sync.yml" \
    "${API_ARGS[@]}" &> /dev/null; then
    echo "✅ $repo configurado correctamente."
  else
    echo "Error: No se pudo crear/actualizar el workflow en $repo." >&2
    continue
  fi

  rm -f "$TMP"
done

echo "Proceso completado."