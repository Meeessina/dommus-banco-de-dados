USE gestaoestoque;
delimiter $$
CREATE TRIGGER saida_sem_estoque
BEFORE INSERT ON movimentacoes_itens
FOR EACH ROW
BEGIN
    DECLARE v_tipo VARCHAR(100);
    DECLARE v_estoque INT;

    SELECT tipo INTO v_tipo
    FROM movimentacoes
    WHERE id_movimentacao = NEW.id_movimentacao;

    SELECT quantidade INTO v_estoque
    FROM produtos
    WHERE id_produto = NEW.id_produto;

    IF v_tipo = 'SAIDA' AND NEW.quantidade > v_estoque THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Estoque insuficiente';
    END IF;
END$$


CREATE TRIGGER atualizar_estoque
AFTER INSERT ON movimentacoes_itens
FOR EACH ROW
BEGIN
    DECLARE v_tipo VARCHAR(10);

    SELECT tipo INTO v_tipo
    FROM movimentacoes
    WHERE id_movimentacao = NEW.id_movimentacao;

    IF v_tipo = 'ENTRADA' THEN
        UPDATE produtos
        SET quantidade = quantidade + NEW.quantidade
        WHERE id_produto = NEW.id_produto;

    ELSEIF v_tipo = 'SAIDA' THEN
        UPDATE produtos
        SET quantidade = quantidade - NEW.quantidade
        WHERE id_produto = NEW.id_produto;

    END IF;
END$$

CREATE TRIGGER auditoria_produtos
AFTER UPDATE ON produtos
FOR EACH ROW
BEGIN
    INSERT INTO logs_auditoria
    (tabela_afetada, operacao, id_registro, valor_anterior, valor_novo, usuario)
    VALUES (
        'produtos',
        'update',
        NEW.id_produto,
        CONCAT('preço: ', OLD.preco, '|quantidade:', OLD.quantidade),
        CONCAT('preço novo: ', NEW.preco, '|quantidade:', NEW.quantidade),
        USER()
    );
END$$

DELIMITER ;

