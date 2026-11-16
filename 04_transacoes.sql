-- Seleciona o banco de dados do sistema de gestao de estoque para criar as procedures e permissoes.
USE gestaoestoque;

-- Remove as procedures caso ja existam para permitir reexecucao limpa deste arquivo.
DROP PROCEDURE IF EXISTS sp_registrar_movimentacao;
DROP PROCEDURE IF EXISTS sp_registrar_movimentacao_lote;
DROP PROCEDURE IF EXISTS sp_reajustar_preco_produto;
DROP PROCEDURE IF EXISTS sp_movimentacao_com_savepoint;

DELIMITER $$

-- Registra uma movimentacao de entrada ou saida de um produto garantindo que cabecalho e item sejam gravados juntos ou desfeitos em caso de erro.
CREATE PROCEDURE sp_registrar_movimentacao(
    IN p_tipo VARCHAR(10),
    IN p_id_usuario INT,
    IN p_id_produto INT,
    IN p_quantidade INT
)
BEGIN
    DECLARE v_id_movimentacao INT;
    DECLARE v_usuario_existe INT DEFAULT 0;
    DECLARE v_produto_existe INT DEFAULT 0;
    DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
    DECLARE v_errno INT DEFAULT 0;
    DECLARE v_mensagem TEXT DEFAULT '';

    -- Captura qualquer falha de trigger ou constraint, desfaz toda a transacao e retorna o motivo do erro.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_sqlstate = RETURNED_SQLSTATE,
            v_errno = MYSQL_ERRNO,
            v_mensagem = MESSAGE_TEXT;
        ROLLBACK;
        SELECT
            'ERRO: Transacao desfeita via ROLLBACK' AS status_transacao,
            v_sqlstate AS sqlstate_erro,
            v_errno AS codigo_erro,
            v_mensagem AS detalhe_erro;
    END;

    START TRANSACTION;

    -- Verifica se o tipo informado corresponde aos valores aceitos pela tabela de movimentacoes.
    IF p_tipo NOT IN ('ENTRADA', 'SAIDA') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Tipo de movimentacao invalido. Use ENTRADA ou SAIDA';
    END IF;

    -- Confere se o usuario responsavel pela operacao esta cadastrado.
    SELECT COUNT(*) INTO v_usuario_existe
    FROM usuarios
    WHERE id_usuario = p_id_usuario;

    IF v_usuario_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Usuario informado nao existe';
    END IF;

    -- Confere se o produto existe na tabela antes de iniciar a movimentacao.
    SELECT COUNT(*) INTO v_produto_existe
    FROM produtos
    WHERE id_produto = p_id_produto;

    IF v_produto_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Produto informado nao existe';
    END IF;

    -- Insere o cabecalho da movimentacao e recupera o identificador gerado.
    INSERT INTO movimentacoes (tipo, id_usuario)
    VALUES (p_tipo, p_id_usuario);

    SET v_id_movimentacao = LAST_INSERT_ID();

    -- Insere o item da movimentacao, disparando as triggers de validacao de saldo, atualizacao de estoque e auditoria.
    INSERT INTO movimentacoes_itens (quantidade, id_produto, id_movimentacao)
    VALUES (p_quantidade, p_id_produto, v_id_movimentacao);

    COMMIT;

    SELECT
        'SUCESSO: Transacao confirmada via COMMIT' AS status_transacao,
        v_id_movimentacao AS id_movimentacao,
        p_tipo AS tipo_movimentacao,
        p_id_produto AS id_produto,
        p_quantidade AS quantidade_movimentada;
END$$

-- Registra uma movimentacao com dois produtos na mesma transacao para garantir atomicidade total entre multiplos itens.
CREATE PROCEDURE sp_registrar_movimentacao_lote(
    IN p_tipo VARCHAR(10),
    IN p_id_usuario INT,
    IN p_id_produto_1 INT,
    IN p_quantidade_1 INT,
    IN p_id_produto_2 INT,
    IN p_quantidade_2 INT
)
BEGIN
    DECLARE v_id_movimentacao INT;
    DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
    DECLARE v_errno INT DEFAULT 0;
    DECLARE v_mensagem TEXT DEFAULT '';

    -- Se o segundo item falhar por falta de estoque, desfaz tambem o cabecalho e o primeiro item ja processado.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_sqlstate = RETURNED_SQLSTATE,
            v_errno = MYSQL_ERRNO,
            v_mensagem = MESSAGE_TEXT;
        ROLLBACK;
        SELECT
            'ERRO NO LOTE: Transacao inteira desfeita via ROLLBACK' AS status_transacao,
            v_sqlstate AS sqlstate_erro,
            v_errno AS codigo_erro,
            v_mensagem AS detalhe_erro;
    END;

    START TRANSACTION;

    IF p_tipo NOT IN ('ENTRADA', 'SAIDA') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Tipo de movimentacao invalido. Use ENTRADA ou SAIDA';
    END IF;

    -- Cria um unico cabecalho de movimentacao para agrupar os dois itens do lote.
    INSERT INTO movimentacoes (tipo, id_usuario)
    VALUES (p_tipo, p_id_usuario);

    SET v_id_movimentacao = LAST_INSERT_ID();

    -- Registra o primeiro item do lote, atualizando seu saldo provisoriamente dentro da transacao.
    INSERT INTO movimentacoes_itens (quantidade, id_produto, id_movimentacao)
    VALUES (p_quantidade_1, p_id_produto_1, v_id_movimentacao);

    -- Registra o segundo item do lote, validando o estoque pela trigger antes de confirmar tudo.
    INSERT INTO movimentacoes_itens (quantidade, id_produto, id_movimentacao)
    VALUES (p_quantidade_2, p_id_produto_2, v_id_movimentacao);

    COMMIT;

    SELECT
        'SUCESSO NO LOTE: Transacao confirmada via COMMIT' AS status_transacao,
        v_id_movimentacao AS id_movimentacao,
        p_tipo AS tipo_movimentacao,
        p_id_produto_1 AS produto_1,
        p_quantidade_1 AS quantidade_1,
        p_id_produto_2 AS produto_2,
        p_quantidade_2 AS quantidade_2;
END$$

-- Atualiza o preco de um produto dentro de uma transacao garantindo que valores invalidos sejam rejeitados.
CREATE PROCEDURE sp_reajustar_preco_produto(
    IN p_id_produto INT,
    IN p_novo_preco DECIMAL(10,2)
)
BEGIN
    DECLARE v_produto_existe INT DEFAULT 0;
    DECLARE v_preco_anterior DECIMAL(10,2);
    DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
    DECLARE v_errno INT DEFAULT 0;
    DECLARE v_mensagem TEXT DEFAULT '';

    -- Desfaz a alteracao caso o preco seja invalido ou ocorra qualquer erro de integridade.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_sqlstate = RETURNED_SQLSTATE,
            v_errno = MYSQL_ERRNO,
            v_mensagem = MESSAGE_TEXT;
        ROLLBACK;
        SELECT
            'ERRO NO REAJUSTE: Transacao desfeita via ROLLBACK' AS status_transacao,
            v_sqlstate AS sqlstate_erro,
            v_errno AS codigo_erro,
            v_mensagem AS detalhe_erro;
    END;

    START TRANSACTION;

    -- Verifica se o produto existe antes de consultar e bloquear o registro para reajuste.
    SELECT COUNT(*) INTO v_produto_existe
    FROM produtos
    WHERE id_produto = p_id_produto;

    IF v_produto_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Produto informado nao existe para reajuste';
    END IF;

    -- Obtem o preco atual bloqueando a linha do produto ate o final da transacao.
    SELECT preco INTO v_preco_anterior
    FROM produtos
    WHERE id_produto = p_id_produto
    FOR UPDATE;

    -- Impede que um produto receba preco zerado ou negativo.
    IF p_novo_preco <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'O novo preco deve ser maior que zero';
    END IF;

    -- Atualiza o preco na tabela de produtos, disparando a trigger de auditoria.
    UPDATE produtos
    SET preco = p_novo_preco
    WHERE id_produto = p_id_produto;

    COMMIT;

    SELECT
        'SUCESSO NO REAJUSTE: Transacao confirmada via COMMIT' AS status_transacao,
        p_id_produto AS id_produto,
        v_preco_anterior AS preco_anterior,
        p_novo_preco AS preco_novo;
END$$

-- Demonstra o uso de SAVEPOINT permitindo manter o item principal caso o item secundario nao tenha estoque suficiente.
CREATE PROCEDURE sp_movimentacao_com_savepoint(
    IN p_tipo VARCHAR(10),
    IN p_id_usuario INT,
    IN p_id_produto_principal INT,
    IN p_qtd_principal INT,
    IN p_id_produto_secundario INT,
    IN p_qtd_secundaria INT
)
BEGIN
    DECLARE v_id_movimentacao INT;
    DECLARE v_estoque_secundario INT DEFAULT 0;
    DECLARE v_status_secundario VARCHAR(100) DEFAULT 'Segundo item processado com sucesso';
    DECLARE v_mensagem TEXT DEFAULT '';

    -- Caso o item principal falhe, desfaz toda a transacao.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_mensagem = MESSAGE_TEXT;
        ROLLBACK;
        SELECT
            'ERRO CRITICO: Transacao inteira desfeita via ROLLBACK' AS status_transacao,
            v_mensagem AS detalhe_erro;
    END;

    START TRANSACTION;

    INSERT INTO movimentacoes (tipo, id_usuario)
    VALUES (p_tipo, p_id_usuario);

    SET v_id_movimentacao = LAST_INSERT_ID();

    -- Grava o item principal da movimentacao.
    INSERT INTO movimentacoes_itens (quantidade, id_produto, id_movimentacao)
    VALUES (p_qtd_principal, p_id_produto_principal, v_id_movimentacao);

    -- Define um ponto de salvamento apos garantir que o item principal foi registrado com sucesso.
    SAVEPOINT ponto_apos_item_principal;

    -- Consulta o saldo do segundo produto para decidir se mantem ou desfaz apenas a parte secundaria.
    SELECT quantidade INTO v_estoque_secundario
    FROM produtos
    WHERE id_produto = p_id_produto_secundario
    FOR UPDATE;

    IF p_tipo = 'SAIDA' AND p_qtd_secundaria > v_estoque_secundario THEN
        ROLLBACK TO SAVEPOINT ponto_apos_item_principal;
        SET v_status_secundario = 'Segundo item descartado via ROLLBACK TO SAVEPOINT por estoque insuficiente';
    ELSE
        INSERT INTO movimentacoes_itens (quantidade, id_produto, id_movimentacao)
        VALUES (p_qtd_secundaria, p_id_produto_secundario, v_id_movimentacao);
    END IF;

    COMMIT;

    SELECT
        'SUCESSO PARCIAL OU TOTAL: Transacao confirmada via COMMIT' AS status_transacao,
        v_id_movimentacao AS id_movimentacao,
        v_status_secundario AS resultado_savepoint;
END$$

DELIMITER ;

-- Concede permissao para que as roles administrativa e operacional possam executar as procedures de transacao.
GRANT EXECUTE ON PROCEDURE gestaoestoque.sp_registrar_movimentacao TO 'administrador'@'%', 'operacional'@'%';
GRANT EXECUTE ON PROCEDURE gestaoestoque.sp_registrar_movimentacao_lote TO 'administrador'@'%', 'operacional'@'%';
GRANT EXECUTE ON PROCEDURE gestaoestoque.sp_reajustar_preco_produto TO 'administrador'@'%', 'operacional'@'%';
GRANT EXECUTE ON PROCEDURE gestaoestoque.sp_movimentacao_com_savepoint TO 'administrador'@'%', 'operacional'@'%';
