# FiapGames.InfraOrchestrator

## Arquitetura Azure atual

Este repositorio provisiona a base de producao do FCG com Terraform:

- Azure API Management `apim-fiapgames-prod` como unica entrada externa;
- rotas `/users`, `/catalog` e `/payment`;
- validacao JWT RS256 por OpenID/JWKS e rate limit no gateway;
- Container Apps restritos ao IP publico do APIM;
- Azure Container Registry Basic;
- Azure Key Vault com RBAC e identidade gerenciada;
- quatro bancos Azure SQL Basic, um por servico;
- RabbitMQ interno com uma replica;
- Log Analytics com quota diaria de `0.1 GB`;
- Container Apps Environment compartilhado.

Gateway publico:

```text
https://apim-fiapgames-prod.azure-api.net
```

Antes de executar Terraform, copie `terraform.tfvars.example` para `terraform.tfvars` e preencha os valores sensiveis. O arquivo real e ignorado pelo Git. Use `configure_apim_apis = true` somente depois que Auth, Catalog e Payment existirem e responderem ao Swagger.

```powershell
C:\terraform\terraform.exe init
C:\terraform\terraform.exe plan -var-file=terraform.tfvars -out=production.tfplan
C:\terraform\terraform.exe apply production.tfplan
```

Testes esperados: JWKS via `/users/.well-known/jwks` retorna `200`, Catalog sem token retorna `401` e qualquer acesso direto aos FQDNs das APIs retorna `403`.

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

## Persistência poliglota e cache

A arquitetura foi evoluída para combinar o melhor de cada tipo de armazenamento:

- SQL Server continua como fonte da verdade para Auth, Catalog e Payment.
- Redis foi adicionado ao Catalog para cache de leitura quente de jogos, promoções e biblioteca do usuário.
- Cosmos DB com API MongoDB foi preparado para o Notification para armazenar histórico de notificações e eventos.

Configuração esperada nos appsettings:

```json
{
  "Redis": { "ConnectionString": "<redis-host>:6380,password=<senha>,ssl=True,abortConnect=False" },
  "MongoDb": {
    "ConnectionString": "mongodb://<cosmos-account>.mongo.cosmos.azure.com:10255/?ssl=true&replicaSet=globaldb&retrywrites=false&maxIdleTimeMS=120000&appName=@<nome>",
    "DatabaseName": "fiapgames_notifications",
    "CollectionName": "HistoricoNotificacoes"
  }
}
```

## Observabilidade

A stack escolhida para a Fase 3 e Prometheus + Grafana, hospedados no mesmo
Azure Container Apps Environment para reduzir custo operacional. Os APIs Auth,
Catalog e Payment expoem metricas HTTP em `/metrics`; o Prometheus coleta essas
rotas pelo APIM, mantendo o gateway como unica entrada externa. O Grafana usa
o Prometheus como datasource e provisiona o dashboard `FIAP Games - API
Overview` automaticamente.

Metricas principais:

- requests por segundo por API;
- percentual de respostas HTTP 5xx;
- latencia P95;
- total de requests no periodo selecionado.

Os endpoints de negocio continuam protegidos por JWT. Apenas `GET /metrics`
fica liberado na politica do APIM para permitir o scrape interno; os Container
Apps continuam restritos ao IP do gateway.

A Notification nao e um quarto API: sua migracao para Azure Function foi
concluida no repositorio `FiapGames.Notification`. A Function usa Service Bus
triggers e envia logs para Application Insights conectado ao Log Analytics
compartilhado, com `FunctionName` e `InvocationId` para correlacao de cada
execucao.

Depois do apply do Terraform, a URL do Grafana e exibida no output
`grafana_url`. O usuario padrao e `admin`; a senha vem de
`grafana_admin_password` ou, quando omitida, da senha do RabbitMQ. Em producao,
defina `grafana_admin_password` explicitamente em um arquivo de variaveis fora
do Git.

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
