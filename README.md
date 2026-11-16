# dommus-banco-de-dados

Este repositório reúne os scripts SQL do banco de dados `gestaoestoque`, desenvolvido em MySQL 8.0 para controlar produtos, fornecedores, categorias, movimentações de entrada e saída e auditoria automática de alterações.

## Por que este projeto existe

Criamos este banco para o projeto final de Banco de Dados (AF2). O objetivo é garantir que o saldo de estoque nunca fique negativo, que cada alteração de preço ou quantidade seja registrada em log de auditoria e que operações compostas rodem dentro de transações seguras com controle de acesso por perfil.

## Como rodar

Abra o MySQL Workbench ou o cliente de linha de comando do MySQL 8.0 conectado com um usuário administrador e execute os arquivos na ordem numérica abaixo:

1. `01_estrutura.sql` cria o banco `gestaoestoque`, as tabelas (`categorias`, `fornecedores`, `usuarios`, `produtos`, `movimentacoes`, `movimentacoes_itens` e `logs_auditoria`), a view `vw_consulta_produtos` e a carga inicial de dados.
2. `02_seguranca.sql` configura as roles (`administrador`, `operacional` e `auditor`), cria os usuários locais e aplica os privilégios de cada perfil.
3. `03_triggers.sql` cria as triggers `saida_sem_estoque`, `atualizar_estoque` e `auditoria_produtos`.
4. `04_transacoes.sql` cria as stored procedures transacionais (`sp_registrar_movimentacao`, `sp_registrar_movimentacao_lote`, `sp_reajustar_preco_produto` e `sp_movimentacao_com_savepoint`) e concede permissão de execução às roles.
5. `05_testes.sql` executa o roteiro de testes comentado e a demonstração integrada validando permissões, triggers, confirmações (`COMMIT`), reversões (`ROLLBACK`) e pontos de salvamento (`SAVEPOINT`).

## Como usar

Para registrar uma entrada ou saída simples com validação e controle de transação, chame a procedure principal passando o tipo da operação, o identificador do usuário, o identificador do produto e a quantidade:

```sql
CALL sp_registrar_movimentacao('ENTRADA', 1, 1, 10);
CALL sp_registrar_movimentacao('SAIDA', 1, 1, 4);
```

Para movimentar dois itens na mesma transação atômica ou reajustar preços com registro automático em `logs_auditoria`, utilize:

```sql
CALL sp_registrar_movimentacao_lote('SAIDA', 1, 1, 1, 2, 3);
CALL sp_reajustar_preco_produto(1, 550.00);
```

Este projeto é composto apenas por scripts SQL e não possui interface gráfica própria. Caso deseje anexar capturas de tela da execução no MySQL Workbench para o relatório técnico, salve as imagens na pasta `docs/` e referencie neste arquivo.

## Histórico recente

15/11/2026: Adicionados os arquivos `04_transacoes.sql` (stored procedures e controle transacional) e `05_testes.sql` (roteiro de testes comentado com demonstração integrada).
