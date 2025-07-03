DO $$
DECLARE
  esquema TEXT := '{{esquema}}';
  tabla TEXT := '{{tabla}}';
  hay_duplicados BOOLEAN;
  hay_nulas BOOLEAN;
  hay_invalidas BOOLEAN;
  sql TEXT;
BEGIN
  -- Verificar geometrías duplicadas
  sql := format($f$
    SELECT EXISTS (
      SELECT 1 FROM %I.%I a
      JOIN %I.%I b
        ON a.ctid <> b.ctid AND ST_Equals(a.geom, b.geom)
      LIMIT 1
    )
  $f$, esquema, tabla, esquema, tabla);
  EXECUTE sql INTO hay_duplicados;

  IF hay_duplicados THEN
    RAISE NOTICE '❌ Existen geometrías duplicadas en %.%', esquema, tabla;
  ELSE
    RAISE NOTICE '✅ No se encontraron geometrías duplicadas en %.%.', esquema, tabla;
  END IF;

  -- Verificar geometrías nulas
  sql := format($f$
    SELECT EXISTS (
      SELECT 1 FROM %I.%I
      WHERE geom IS NULL
      LIMIT 1
    )
  $f$, esquema, tabla);
  EXECUTE sql INTO hay_nulas;

  IF hay_nulas THEN
    RAISE NOTICE '❌ Existen geometrías nulas en %.%.', esquema, tabla;
  ELSE
    RAISE NOTICE '✅ No se encontraron geometrías nulas en %.%.', esquema, tabla;
  END IF;

  -- Verificar geometrías inválidas
  sql := format($f$
    SELECT EXISTS (
      SELECT 1 FROM %I.%I
      WHERE NOT ST_IsValid(geom)
      LIMIT 1
    )
  $f$, esquema, tabla);
  EXECUTE sql INTO hay_invalidas;

  IF hay_invalidas THEN
    RAISE NOTICE '❌ Existen geometrías inválidas en %.%.', esquema, tabla;
  ELSE
    RAISE NOTICE '✅ No se encontraron geometrías inválidas en %.%.', esquema, tabla;
  END IF;
END$$;
