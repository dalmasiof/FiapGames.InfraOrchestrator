# Roteiro de vídeo — FIAP Cloud Games

Use `FCG-Video.postman_collection.json` com o environment `FCG-Video.postman_environment.json`. A collection está separada em pastas para deixar clara a ordem e a pausa do live deploy.

## Antes de gravar

1. Inicie o ambiente com `scripts/resume-environment.ps1` se ele estiver suspenso. Confirme no Azure Portal o AKS e, no terminal, `kubectl get pods -o wide`. Os IPs do environment Postman foram preenchidos com os IPs atuais dos Load Balancers; confira depois de cada resume.
2. Importe a collection e o environment e selecione `FIAP Video - Azure` como ambiente ativo. Ele usa uma conta de demonstração existente (`postman@example.com`) para autenticar e reproduzir o cadastro duplicado. Não rode a collection inteira de uma vez.
3. No Catalog, a lista de jogos fica em cache Redis por cinco minutos. Para mostrar miss/hit com mais clareza, limpe a chave `FiapGamesCatalog:catalog:jogos:todos` no Redis antes da gravação. A collection registra os tempos da primeira e da segunda chamada no Postman Console.

## Gravação

1. **Infra Azure e Kubernetes:** mostre a assinatura, o AKS gerenciado, os pods Auth/Catalog/RabbitMQ e os serviços LoadBalancer. Explique que Auth e Catalog acessam o AKS.
2. **Erro antes do deploy:** abra a pasta `1 - Antes do live deploy` e execute `1. Login - Usuario existente`, depois `2. Cadastro duplicado - antes do deploy (espera 500)`. O e-mail já existe; a versão atual expõe a violação da chave única como HTTP 500.
3. **Ajuste em tempo real e CI/CD:** no repositório Auth, implemente o tratamento explícito de e-mail duplicado para responder HTTP 409 Conflict. Faça commit e push para `main`. Mostre a GitHub Action `Deploy Auth API to AKS`: build/test, imagem no ACR e rollout no AKS. Espere o workflow concluir antes da próxima chamada.
4. **Verificação após o deploy:** execute `3. Repetir cadastro duplicado - depois do deploy (espera 409)`. O método, endpoint e body são os mesmos; a resposta deve passar de 500 para 409.
5. **Cache do Catalog:** na pasta `3 - Busca e cache do Catalog`, execute as duas listagens seguidas e compare `Leitura 1 / ms` e `Leitura 2 / ms` no Postman Console e na aba Timing. Explique a chave, o TTL de cinco minutos e que gravações invalidam o cache.
6. **Busca avançada:** execute `3. Catalog - Busca fuzzy (termo com erro)`. O environment usa `Minecraf` como erro proposital para encontrar `Minecraft` pela busca fuzzy do Elasticsearch.
7. **NoSQL:** mostre a Function de notificações e a coleção `HistoricoNotificacoes` no MongoDB. O projeto usa `MongoDB.Driver` nessa Function; não há endpoint HTTP de consulta para demonstrar esse histórico no Postman.

## Pausa entre as chamadas de cadastro

Não execute a pasta 2 antes do ajuste e do rollout. O cadastro inicial é intencionalmente duplicado e deve reproduzir o erro da versão atual; depois do deploy, a repetição deve demonstrar o tratamento novo. A collection completa `FCG-Azure.postman_collection.json` foi mantida separada para chamadas fora do roteiro.




