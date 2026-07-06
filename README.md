# FiapGames.InfraOrchestrator

Repositório responsável por orquestrar os serviços locais do workspace FiapGames.

## Objetivo

- Subir a infraestrutura comum de mensageria e bancos
- Iniciar os serviços existentes com base em uma árvore local fixa
- Permitir bootstrap automático via script a partir de `C:\git\FiapGames_MS`

## Como usar

No Windows:

```powershell
cd c:\git\FiapGames_MS\FiapGames.InfraOrchestrator
./bootstrap.ps1
```

No Linux/macOS:

```bash
cd /c/git/FiapGames_MS/FiapGames.InfraOrchestrator
./bootstrap.sh
```

## O que está incluído

- `docker-compose.yml` com RabbitMQ, SQL Server e os serviços:
  - AuthService
  - PaymentService
  - Catalog
  - Notification
- `bootstrap.ps1` para validação do workspace e deploy
- `bootstrap.sh` equivalente para ambientes Unix

## Observações

- Os repositórios devem existir previamente em `C:\git\FiapGames_MS`:
  - `FiapGame.AuthService`
  - `FiapGame.PaymentService`
  - `FiapGames.Catalog`
  - `FiapGames.Notification`
- O bootstrap não faz clone nem pull; ele só valida a árvore local e sobe a stack.

## Variáveis de ambiente (Docker Compose)

O `docker-compose.yml` foi parametrizado para evitar segredos fixos em arquivo.

Principais variáveis:

- `SQLSERVER_SA_PASSWORD`
- `RABBITMQ_DEFAULT_USER`
- `RABBITMQ_DEFAULT_PASS`
- `RABBITMQ_USERNAME`
- `RABBITMQ_PASSWORD`
- `JWT_KEY`
- `JWT_ISSUER`
- `JWT_AUDIENCE`
- `AUTH_CONNECTION_STRING`
- `PAYMENT_CONNECTION_STRING`
- `CATALOG_CONNECTION_STRING`
- `NOTIFICATION_CONNECTION_STRING`

## Fluxo Kubernetes (manifests agregados)

Em `k8s/`, os serviços de API/worker usam `ConfigMap` para não sensíveis e `Secret` para sensíveis.

Arquivos adicionados para padronização:

- `auth-api-configmap.yaml` e `auth-api-secret.yaml`
- `catalog-api-configmap.yaml` e `catalog-api-secret.yaml`
- `payment-api-configmap.yaml` e `payment-api-secret.yaml`
- `notification-worker-configmap.yaml` e `notification-worker-secret.yaml`
- `rabbitmq-configmap.yaml` e `rabbitmq-secret.yaml`
- `sqlserver-configmap.yaml` e `sqlserver-secret.yaml`

Ordem sugerida para apply (quando for executar em cluster):

1. ConfigMaps e Secrets
2. RabbitMQ e SQL Server
3. APIs e worker de notificação

## Checklist de execução limpa (final)

### 1) Preparar variáveis locais

Use `.env.example` como base:

```powershell
cp .env.example .env
```

Defina valores reais para:

- `SQLSERVER_SA_PASSWORD`
- `RABBITMQ_DEFAULT_USER`
- `RABBITMQ_DEFAULT_PASS`
- `RABBITMQ_USERNAME`
- `RABBITMQ_PASSWORD`
- `JWT_KEY`
- `JWT_ISSUER`
- `JWT_AUDIENCE`
- `AUTH_CONNECTION_STRING`
- `PAYMENT_CONNECTION_STRING`
- `CATALOG_CONNECTION_STRING`
- `NOTIFICATION_CONNECTION_STRING`

Os scripts `apply-secrets.ps1` e `run-clean-validation.ps1` carregam `.env` automaticamente a partir da raiz deste repositório.

### 2) Docker limpo

No diretório deste repositório:

```powershell
docker compose down -v --remove-orphans
docker compose up -d --build
docker compose ps
docker compose logs --tail=200
```

Ou execute em modo automatizado:

```powershell
./scripts/run-clean-validation.ps1 -Mode docker -Clean
```

Critério: serviços estáveis, sem loop de erro de conexão com SQL ou RabbitMQ.

### 3) Kubernetes limpo

Aplicar primeiro ConfigMaps/Secrets e depois Deployments/Services:

```powershell
kubectl apply -f k8s/*configmap.yaml
./scripts/apply-secrets.ps1
kubectl apply -f k8s/*deployment.yaml
kubectl apply -f k8s/*service.yaml
kubectl get pods,svc
```

Ou execute em modo automatizado:

```powershell
./scripts/run-clean-validation.ps1 -Mode k8s -Clean
```

Critério: pods `Ready` e sem reinícios inesperados.

### 4) Smoke ponta a ponta

Fluxo mínimo:

1. Gerar token no Auth
2. Criar compra no Catalog
3. Confirmar processamento no Payment
4. Confirmar consumo no Notification

Critério: mesmo `RastreioId/CorrelationId` observável nos logs dos serviços envolvidos.
