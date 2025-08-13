/*
********************************************************************************
* Código: identificar dangles
* Autor: Jhoinner Manrique
* Fecha de creación: 29-07-2025
* Última modificación: 29-07-2025
* Versión: 1.1
********************************************************************************
*/

--Cambiar "{capa}" por el esquema incluyendo las comillas
--cambiar "{capa}" por el nombre de la capa incluyendo las comillas

--preparar capa
DROP TABLE IF EXISTS mavvial_dangles;

CREATE TABLE mavvial_dangles AS
SELECT DISTINCT ON (ST_AsBinary(geom_part)) 
       row_number() OVER () AS id,
       geom_part AS geom
FROM (
    SELECT (ST_Dump(geom)).geom AS geom_part
    FROM "{esquema}"."{capa}"
) sub
ORDER BY ST_AsBinary(geom_part);



create index idex_geom_mavvial_dangles on mavvial_dangles using gist (geom);
alter table mavvial_dangles drop column if exists id;
alter table mavvial_dangles add column id serial;

----------------------------------------------------------------------------------
--CREAR TABLA CON PUNTOS INICIALES
DROP TABLE IF EXISTS start_point_mavvial;
CREATE TABLE start_point_mavvial AS
SELECT
	id,-- o el ID que tengas en la tabla original
    ST_StartPoint(geom) AS geom
FROM mavvial_dangles;

ALTER TABLE start_point_mavvial
ALTER COLUMN geom TYPE geometry(Point, 4326)
USING geom::geometry(Point, 4326); 

----------------------------------------------------------------------------------
--CREAR TABLA CON PUNTOS FINALES
DROP TABLE IF EXISTS end_point_mavvial;
CREATE TABLE end_point_mavvial AS
SELECT
	id,
    ST_EndPoint(ST_LineMerge(geom)) AS geom
FROM mavvial_dangles;

ALTER TABLE end_point_mavvial
ALTER COLUMN geom TYPE geometry(Point, 4326)
USING geom::geometry(Point, 4326); 

----------------------------------------------------------------------------------
-- CREAR TABLA DANGLES CONSOLIDADA

DROP TABLE IF EXISTS ptos_dangles;

CREATE TABLE ptos_dangles (
    id SERIAL,
    geom GEOMETRY(POINT, 4326)
);

-- 2. Insertar registros desde end_point_mavvial
INSERT INTO ptos_dangles (id, geom)
SELECT id, geom
FROM end_point_mavvial;

-- 3. Insertar registros desde start_point_mavvial
INSERT INTO ptos_dangles (id, geom)
SELECT id, geom
FROM start_point_mavvial;

-- crear indice espacial
create index idx_ptos_dangles on ptos_dangles using gist (geom);

------------------------------------------------------------------
-- crear tabla que conserva todos los extremos
drop table if exists ptos_extremos;
create table ptos_extremos as
select * from ptos_dangles;

create index idx_ptos_extremos on ptos_extremos using gist (geom);

DELETE FROM ptos_extremos
WHERE ctid IN (
  SELECT ctid
  FROM (
    SELECT ctid,
           ROW_NUMBER() OVER (PARTITION BY ST_AsEWKT(geom)) AS fila
    FROM ptos_extremos
  ) sub
  WHERE sub.fila > 1
);

reindex table ptos_extremos;

-- borrar capas de start y end
drop table end_point_mavvial;
drop table start_point_mavvial;

-----------------------------------------------------------------------------
--depurar extremos que conectan

DELETE FROM ptos_dangles
WHERE ST_AsEWKT(geom) IN (
  SELECT geom_text
  FROM (
    SELECT ST_AsEWKT(geom) AS geom_text, COUNT(*) AS cantidad
    FROM ptos_dangles
    GROUP BY geom_text
    HAVING COUNT(*) > 1
  ) repetidos
);

reindex table ptos_dangles;

-----------------------------------------------------------------------------
--dangles mas probables

DROP TABLE IF EXISTS dangles_verdaderos;

CREATE TABLE dangles_verdaderos AS
SELECT * FROM ptos_dangles WHERE false;  

--------------------------------------------
DO $$
DECLARE
  lote RECORD;
  lote_size INTEGER := 1000;
  offset_value INTEGER := 0;
  total_rows INTEGER;
  insertados_lote INTEGER := 0;
  lote_num INTEGER := 1;
BEGIN
  -- Obtener cantidad total de puntos
  SELECT COUNT(*) INTO total_rows FROM ptos_dangles;
  RAISE NOTICE 'Total de puntos a procesar: %', total_rows;

  WHILE offset_value < total_rows LOOP
    insertados_lote := 0;

    FOR lote IN
      SELECT p.*
      FROM ptos_dangles p
      ORDER BY ctid
      OFFSET offset_value LIMIT lote_size
    LOOP
      IF EXISTS (
        SELECT 1
        FROM mavvial_dangles l
        WHERE ST_DWithin(lote.geom, l.geom, 0.00004483)
          AND lote.id <> l.id
      ) THEN
        INSERT INTO dangles_verdaderos(id, geom)
        VALUES (lote.id, lote.geom);
        insertados_lote := insertados_lote + 1;
      END IF;
    END LOOP;

    RAISE NOTICE 'Lote % procesado. Insertados: %', lote_num, insertados_lote;

    offset_value := offset_value + lote_size;
    lote_num := lote_num + 1;
  END LOOP;

  RAISE NOTICE 'Proceso finalizado.';
END$$;

------------------------------------------------------------------------
-- Alojar dangles en el esquema-----------------------------------------
------------------------------------------------------------------------

drop table if exists "{esquema}".dangles_totales_{capa};
create table "{esquema}".dangles_totales_{capa} as
select * from ptos_dangles;

create index idx_geom_dangles on "{esquema}".dangles_totales_{capa} using gist (geom);

------------------------------------------------------------------------
--------Crear capa de dangles verdaderos--------------------------------
------------------------------------------------------------------------
drop table if exists "{esquema}".dangle_verdadero_{capa};
create table "{esquema}".dangle_verdadero_{capa} as
select * from dangles_verdaderos;

create index idx_geom_dangle_verdadero on "{esquema}".dangle_verdadero_{capa} using gist (geom);

------------------------------------------------------------------------
---------------Borrar capas temporales----------------------------------
------------------------------------------------------------------------

drop table dangles_verdaderos;
drop table mavvial_dangles;
drop table ptos_dangles;
drop table ptos_extremos;
