-- Seleciona o banco de dados principal para executar a bateria de testes e a demonstracao integrada.
USE gestaoestoque;

-- Consulta o estado inicial dos produtos pela view e dos registros de movimentacao e auditoria antes dos testes.
SELECT * FROM vw_consulta_produtos;
SELECT * FROM produtos;
SELECT * FROM movimentacoes;
SELECT * FROM movimentacoes_itens;
SELECT * FROM logs_auditoria;

-- Verifica as permissoes atribuidas aos perfis de acesso e aos usuarios criados no script de seguranca.
SHOW GRANTS FOR 'administrador'@'%';
SHOW GRANTS FOR 'operacional'@'%';
SHOW GRANTS FOR 'auditor'@'%';
SHOW GRANTS FOR 'user_admin'@'localhost';
SHOW GRANTS FOR 'user_operacional'@'localhost';
SHOW GRANTS FOR 'user_auditor'@'localhost';

-- Testa a consulta na view permitida para o perfil de auditoria, exibindo produto, categoria, fornecedor, preco e saldo.
SELECT nome, categoria, fornecedor, preco, quantidade
FROM vw_consulta_produtos;

-- Testa a entrada de estoque via procedure transacional, confirmando a soma do saldo pela trigger atualizar_estoque e o registro em logs_auditoria.
CALL sp_registrar_movimentacao('ENTRADA', 1, 1, 10);

-- Confere o saldo atualizado do produto 1 e o novo registro gravado automaticamente na tabela de auditoria.
SELECT id_produto, nome, preco, quantidade FROM produtos WHERE id_produto = 1;
SELECT * FROM logs_auditoria ORDER BY id_log DESC LIMIT 2;

-- Testa uma saida valida de estoque dentro do limite disponivel para confirmar a baixa automatica do saldo.
CALL sp_registrar_movimentacao('SAIDA', 1, 1, 4);

-- Confere o saldo do produto 1 apos a saida valida e verifica o historico de auditoria gerado pela trigger.
SELECT id_produto, nome, preco, quantidade FROM produtos WHERE id_produto = 1;
SELECT * FROM logs_auditoria ORDER BY id_log DESC LIMIT 2;

-- Testa o bloqueio da trigger saida_sem_estoque solicitando uma quantidade maior que o saldo disponivel, acionando o ROLLBACK na procedure.
CALL sp_registrar_movimentacao('SAIDA', 1, 1, 999);

-- Comprova que o ROLLBACK desfez o cabecalho da movimentacao e manteve intactos o saldo do produto e a tabela de logs.
SELECT id_produto, nome, preco, quantidade FROM produtos WHERE id_produto = 1;
SELECT * FROM movimentacoes ORDER BY id_movimentacao DESC LIMIT 3;
SELECT * FROM logs_auditoria ORDER BY id_log DESC LIMIT 3;

-- Testa a validacao da constraint CHECK de quantidade positiva na tabela movimentacoes_itens tentando informar quantidade zero.
CALL sp_registrar_movimentacao('ENTRADA', 1, 1, 0);

-- Testa o reajuste de preco valido via procedure transacional, disparando a trigger auditoria_produtos.
CALL sp_reajustar_preco_produto(1, 550.00);

-- Testa a tentativa de reajuste com preco negativo ou zerado para comprovar que a transacao e desfeita via ROLLBACK.
CALL sp_reajustar_preco_produto(1, -50.00);

-- Confere que o preco do produto 1 permaneceu em 550.00 e que apenas a alteracao valida entrou no log de auditoria.
SELECT id_produto, nome, preco, quantidade FROM produtos WHERE id_produto = 1;
SELECT * FROM logs_auditoria ORDER BY id_log DESC LIMIT 3;

-- Testa o uso de SAVEPOINT onde o primeiro item possui estoque suficiente e o segundo item excede o saldo, mantendo apenas o primeiro item.
CALL sp_movimentacao_com_savepoint('SAIDA', 1, 2, 2, 1, 800);

-- Confere que apenas a saida de 2 unidades do produto 2 foi confirmada, enquanto o produto 1 nao sofreu alteracao.
SELECT id_produto, nome, preco, quantidade FROM produtos;

-- Inicia a demonstracao integrada ponta a ponta reunindo seguranca, procedures, transacoes, triggers, view e auditoria.
-- Passo 1 da demonstracao integrada: registra a fotografia completa do banco antes das operacoes em lote.
SELECT
    (SELECT COUNT(*) FROM movimentacoes) AS total_movimentacoes_antes,
    (SELECT COUNT(*) FROM movimentacoes_itens) AS total_itens_antes,
    (SELECT COUNT(*) FROM logs_auditoria) AS total_logs_antes;

SELECT * FROM vw_consulta_produtos;

-- Passo 2 da demonstracao integrada: executa uma movimentacao em lote valida retirando 1 unidade do produto 1 e 3 unidades do produto 2 na mesma transacao.
CALL sp_registrar_movimentacao_lote('SAIDA', 1, 1, 1, 2, 3);

-- Passo 3 da demonstracao integrada: verifica que o COMMIT confirmou o cabecalho, os dois itens, a baixa nos dois produtos e os dois registros de auditoria.
SELECT * FROM vw_consulta_produtos;
SELECT * FROM movimentacoes ORDER BY id_movimentacao DESC LIMIT 2;
SELECT * FROM movimentacoes_itens ORDER BY id_movimentacao_item DESC LIMIT 4;
SELECT * FROM logs_auditoria ORDER BY id_log DESC LIMIT 4;

-- Guarda os contadores apos o lote valido para comparar com o proximo teste de falha atomica.
SELECT
    (SELECT COUNT(*) FROM movimentacoes) AS total_movimentacoes_pos_sucesso,
    (SELECT COUNT(*) FROM movimentacoes_itens) AS total_itens_pos_sucesso,
    (SELECT COUNT(*) FROM logs_auditoria) AS total_logs_pos_sucesso;

-- Passo 4 da demonstracao integrada: executa um lote onde o primeiro item e valido (1 unidade do produto 2) mas o segundo item estoura o estoque (500 unidades do produto 1).
-- Mesmo com o primeiro item tendo atualizado o estoque e gerado log durante a execucao, a falha da trigger no segundo item forca o ROLLBACK completo de tudo.
CALL sp_registrar_movimentacao_lote('SAIDA', 1, 2, 1, 1, 500);

-- Passo 5 da demonstracao integrada: comprova que nenhum dado orfao ficou gravado em movimentacoes, movimentacoes_itens, produtos ou logs_auditoria.
SELECT
    (SELECT COUNT(*) FROM movimentacoes) AS total_movimentacoes_pos_rollback,
    (SELECT COUNT(*) FROM movimentacoes_itens) AS total_itens_pos_rollback,
    (SELECT COUNT(*) FROM logs_auditoria) AS total_logs_pos_rollback;

SELECT * FROM vw_consulta_produtos;
SELECT * FROM logs_auditoria ORDER BY id_log DESC LIMIT 4;

-- Demonstra tambem um bloco manual de transacao explicita com START TRANSACTION e ROLLBACK para validacao direta no cliente SQL.
START TRANSACTION;
UPDATE produtos SET preco = 9999.99 WHERE id_produto = 2;
SELECT id_produto, nome, preco FROM produtos WHERE id_produto = 2;
ROLLBACK;
SELECT id_produto, nome, preco FROM produtos WHERE id_produto = 2;
