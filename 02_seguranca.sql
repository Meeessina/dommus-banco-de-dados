
USE gestaoestoque;


CREATE ROLE IF NOT EXISTS
    'administrador'@'%',
    'operacional'@'%',
    'auditor'@'%';
    
  
CREATE USER IF NOT EXISTS 'user_admin'@'localhost'
IDENTIFIED BY '12345';

CREATE USER IF NOT EXISTS 'user_operacional'@'localhost'
IDENTIFIED BY '12345';

CREATE USER IF NOT EXISTS 'user_auditor'@'localhost'
IDENTIFIED BY '12345';


GRANT ALL PRIVILEGES ON gestaoestoque.*
TO 'administrador'@'%';

-- Permissoes do operacional
GRANT SELECT, INSERT, UPDATE ON gestaoestoque.*
TO 'operacional'@'%';

-- Permissoes do auditor
GRANT SELECT ON gestaoestoque.vw_consulta_produtos
TO 'auditor'@'%';


GRANT 'administrador'@'%' TO 'user_admin'@'localhost';
GRANT 'operacional'@'%' TO 'user_operacional'@'localhost';
GRANT 'auditor'@'%' TO 'user_auditor'@'localhost';


SET DEFAULT ROLE 'administrador'@'%'
TO 'user_admin'@'localhost';

SET DEFAULT ROLE 'operacional'@'%'
TO 'user_operacional'@'localhost';

SET DEFAULT ROLE 'auditor'@'%'
TO 'user_auditor'@'localhost';


GRANT DELETE ON gestaoestoque.produtos
TO 'operacional'@'%';

REVOKE DELETE ON gestaoestoque.produtos
FROM 'operacional'@'%';


SHOW GRANTS FOR 'administrador'@'%';
SHOW GRANTS FOR 'operacional'@'%';
SHOW GRANTS FOR 'auditor'@'%';

SHOW GRANTS FOR 'user_admin'@'localhost';
SHOW GRANTS FOR 'user_operacional'@'localhost';
SHOW GRANTS FOR 'user_auditor'@'localhost';
