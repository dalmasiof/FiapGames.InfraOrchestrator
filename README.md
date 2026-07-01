# FiapGames.InfraOrchestrator

Repositório responsável por orquestrar os serviços locais do workspace FiapGames.

## Objetivo

- Subir a infraestrutura comum de mensageria e bancos
- Construir e iniciar os serviços existentes em outros repositórios
- Permitir bootstrap automático via script

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
- `bootstrap.ps1` para verificação de repositórios e deploy
- `bootstrap.sh` equivalente para ambientes Unix

## Observações

- Os repositórios são esperados dentro de `c:\git\FiapGames_MS`.
- Ajuste URLs de clone no `bootstrap.ps1` se quiser que ele faça clone automático.
- O script `bootstrap.sh` não faz clone automático hoje; mantém apenas pull dos repositórios existentes.
